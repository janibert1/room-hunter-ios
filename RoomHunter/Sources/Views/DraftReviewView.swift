import SwiftUI
import PhotosUI

/// Loaded after "Yes". Shows the editable draft (Gemini's <=3 personalized
/// sentences highlighted, per Jan's spec) and requires an explicit confirm
/// step before the real send -- this is the one screen in the whole app
/// where a mis-tap has a real consequence (a message actually reaching a
/// real stranger), so "Send" opens a confirmation alert rather than firing
/// immediately.
struct DraftReviewView: View {
    let candidateId: String
    let api: APIClient
    let onSentOrCancelled: () -> Void

    @State private var draftText: String = ""
    @State private var highlightSpans: [HighlightSpan] = []
    @State private var loadToken = 0
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showSendConfirm = false

    // 2026-08-30, Jan's explicit ask: preview + change which of his own
    // profile photos get sent alongside the message. Loaded separately
    // from the draft itself (own endpoint, own failure mode) -- a photo
    // load failure shouldn't block reviewing/sending the text.
    @State private var photos: [ProfilePhoto] = []
    @State private var photosErrorMessage: String?

    // 2026-08-30, second ask same day: "i also want to be able to add
    // more photos of my own." pickerItem drives upload; longPressTarget
    // drives delete (a destructive action, so it goes through a real
    // confirmation dialog rather than firing on the long-press itself).
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var deleteTarget: ProfilePhoto?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading draft…")
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Circle().fill(Color(HighlightedTextEditor.highlightColor)).frame(width: 10, height: 10)
                            Text("Highlighted = Gemini's personalization").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        HighlightedTextEditor(text: $draftText, highlightSpans: highlightSpans, loadToken: loadToken)
                            .onChange(of: draftText) { _, newValue in
                                Task { await saveEdit(newValue) }
                            }

                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red).font(.callout).padding(.horizontal)
                        }

                        photoPicker
                    }
                }
            }
            .navigationTitle("Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onSentOrCancelled() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showSendConfirm = true
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Send").bold()
                        }
                    }
                    .disabled(isLoading || isSending || draftText.isEmpty)
                }
            }
            .confirmationDialog(
                "Send this message?",
                isPresented: $showSendConfirm,
                titleVisibility: .visible
            ) {
                Button("Send for real", role: .destructive) {
                    Task { await send() }
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("This actually sends the message above to the landlord/poster. Not a preview.")
            }
        }
        .task {
            await load()
            await loadPhotos()
        }
    }

    /// Sent alongside every real message (see profile_photos.py
    /// server-side) -- a horizontal strip of Jan's own profile photos,
    /// each with a checkmark when selected. Tapping toggles it and saves
    /// immediately (global setting, not scoped to this one candidate, so
    /// there's no separate "save" step to forget).
    @ViewBuilder
    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photos sent with this message").font(.caption).foregroundStyle(.secondary)
            if let photosErrorMessage {
                Text(photosErrorMessage).font(.caption).foregroundStyle(.red)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        Button {
                            Task { await togglePhoto(photo) }
                        } label: {
                            photoThumbnail(photo)
                        }
                        .buttonStyle(.plain)
                        // Long-press to delete -- a destructive action, so
                        // it opens a real confirmation rather than firing
                        // on the press itself (same standard as Send).
                        .onLongPressGesture {
                            deleteTarget = photo
                        }
                    }
                    addPhotoTile
                }
                .padding(.horizontal)
            }
            Text(selectedCountLabel).font(.caption2).foregroundStyle(.tertiary).padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(.bar)
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { Task { await deletePhoto(target) } }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This removes it from your profile photos entirely, not just from this message.")
        }
    }

    private var addPhotoTile: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                if isUploadingPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "plus").font(.system(size: 22)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
        }
        .disabled(isUploadingPhoto)
        .onChange(of: pickerItem) { _, newItem in
            Task { await uploadPicked(newItem) }
        }
    }

    private var selectedCountLabel: String {
        if photos.isEmpty { return "No profile photos yet — tap + to add one" }
        let n = photos.filter(\.selected).count
        if n == 0 { return "None selected — message will send with no photos" }
        return "\(n) of \(photos.count) selected"
    }

    private func photoThumbnail(_ photo: ProfilePhoto) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: URL(string: photo.url)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(photo.selected ? 1.0 : 0.35)

            Image(systemName: photo.selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(photo.selected ? Color.accentColor : .secondary)
                .background(Circle().fill(.white))
                .padding(4)
        }
    }

    func loadPhotos() async {
        do {
            photos = try await api.fetchProfilePhotos()
            photosErrorMessage = nil
        } catch {
            photosErrorMessage = "Couldn't load photos: \(error.localizedDescription)"
        }
    }

    func togglePhoto(_ photo: ProfilePhoto) async {
        guard let idx = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        // Optimistic local flip so the tap feels instant, reconciled
        // against the server's actual saved list right after -- same
        // "server response is the real truth" pattern the rest of the app
        // uses (e.g. reconsiderHistoryEntry), not a blind local-only toggle.
        let wasSelected = photos[idx].selected
        photos[idx] = ProfilePhoto(id: photo.id, url: photo.url, selected: !wasSelected)
        let requestedIds = photos.filter(\.selected).map(\.id)
        do {
            let savedIds = Set(try await api.setProfilePhotoSelection(ids: requestedIds))
            photos = photos.map { ProfilePhoto(id: $0.id, url: $0.url, selected: savedIds.contains($0.id)) }
            photosErrorMessage = nil
        } catch {
            photos[idx] = ProfilePhoto(id: photo.id, url: photo.url, selected: wasSelected)  // revert on failure
            photosErrorMessage = "Couldn't save photo selection: \(error.localizedDescription)"
        }
    }

    /// Re-encodes whatever the picker hands back to JPEG rather than
    /// trusting/detecting the source format -- sidesteps content-type
    /// sniffing entirely (a HEIC photo straight off the camera roll would
    /// otherwise need real format detection) and keeps upload size sane.
    func uploadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingPhoto = true
        photosErrorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data),
                  let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
                photosErrorMessage = "Couldn't read that photo."
                isUploadingPhoto = false
                pickerItem = nil
                return
            }
            let newPhoto = try await api.uploadProfilePhoto(imageData: jpegData, contentType: "image/jpeg")
            photos.append(newPhoto)
        } catch {
            photosErrorMessage = "Couldn't upload photo: \(error.localizedDescription)"
        }
        isUploadingPhoto = false
        pickerItem = nil
    }

    func deletePhoto(_ photo: ProfilePhoto) async {
        do {
            try await api.deleteProfilePhoto(id: photo.id)
            photos.removeAll { $0.id == photo.id }
            photosErrorMessage = nil
        } catch {
            photosErrorMessage = "Couldn't delete photo: \(error.localizedDescription)"
        }
        deleteTarget = nil
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let draft = try await api.fetchDraft(candidateId: candidateId)
            draftText = draft.fullText
            highlightSpans = draft.highlightedSpans
            loadToken += 1
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Debounced-by-nature: SwiftUI's onChange already only fires per real
    /// text change, and this is a personal single-user tool talking to a
    /// server on the same home network -- not worth a real debounce timer
    /// for the save-as-you-type call.
    func saveEdit(_ text: String) async {
        do {
            try await api.saveDraftEdit(candidateId: candidateId, editedText: text)
        } catch {
            // Don't blow away what Jan is actively typing over a transient
            // save failure -- surface it, but the real safeguard is the
            // Send button re-reading draftText (the live UI state) rather
            // than trusting the server's last-saved copy.
            errorMessage = "Couldn't save edit: \(error.localizedDescription)"
        }
    }

    func send() async {
        isSending = true
        errorMessage = nil
        do {
            // Make sure the very latest edit is persisted before the real
            // send, in case saveEdit's last call is still in flight.
            try await api.saveDraftEdit(candidateId: candidateId, editedText: draftText)
            try await api.sendMessage(candidateId: candidateId)
            onSentOrCancelled()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
