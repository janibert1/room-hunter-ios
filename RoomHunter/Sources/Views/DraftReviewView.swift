import SwiftUI

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
        .task { await load() }
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
