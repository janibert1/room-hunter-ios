import SwiftUI

struct CandidateQueueView: View {
    @State private var candidates: [Candidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selected: Candidate?
    @EnvironmentObject private var nav: NavigationCoordinator

    let api = APIClient()

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Queue")
            .task { await load() }
            .onChange(of: nav.pendingCandidateId) { _, newId in
                openPendingIfPossible(newId)
            }
            .sheet(item: $selected) { candidate in
                CandidateDetailView(candidate: candidate, api: api, onDecided: {
                    selected = nil
                    Task { await load() }
                })
            }
        }
    }

    // Extracted out of `body` -- Swift's type-checker choked on the combined
    // conditional+VStack+extra-Text nesting inline (a real, confusing
    // compiler error: "generic parameter could not be inferred" pointing at
    // an unrelated TableColumn overload). Splitting each branch into its
    // own @ViewBuilder property is the standard fix for this class of
    // SwiftUI type-inference complexity issue.
    @ViewBuilder
    private var content: some View {
        if isLoading && candidates.isEmpty {
            ProgressView("Loading…")
        } else if let errorMessage {
            errorState(errorMessage)
        } else if candidates.isEmpty {
            emptyState
        } else {
            candidateList
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Nothing waiting on you").font(.headline).foregroundStyle(.secondary)
            Text("New rooms will show up here").font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    private var candidateList: some View {
        List(candidates) { candidate in
            Button { selected = candidate } label: {
                CandidateRow(candidate: candidate)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .refreshable { await load() }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            candidates = try await api.fetchCandidates()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        // A deep link may have arrived before this load finished (e.g. cold
        // launch from a notification tap) -- resolve it now that we
        // actually have data to look the id up in.
        openPendingIfPossible(nav.pendingCandidateId)
    }

    /// Reacts to NavigationCoordinator.pendingCandidateId, set by the
    /// ntfy deep-link handler in RootView. Deliberately doesn't clear
    /// pendingCandidateId itself on success -- only on a real match, so a
    /// deep link that arrives before candidates finish loading isn't lost.
    private func openPendingIfPossible(_ id: String?) {
        guard let id, let match = candidates.first(where: { $0.id == id }) else { return }
        selected = match
        nav.pendingCandidateId = nil
    }
}

struct CandidateRow: View {
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: candidate.photos.first.flatMap(URL.init)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "house.fill").foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    if let price = candidate.formattedPrice {
                        Text(price).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let location = candidate.location {
                        Text("· \(location)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(candidate.source).font(.caption2).textCase(.uppercase).foregroundStyle(.tertiary)
                    if let postedAtRelative = candidate.postedAtRelative {
                        Text("· Posted \(postedAtRelative)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            ScoreBadge(score: candidate.score)
        }
        .padding(.vertical, 4)
    }
}

struct ScoreBadge: View {
    let score: Int
    var color: Color {
        switch score {
        case 80...: return Color(red: 0.29, green: 0.60, blue: 0.36) // considered green, not system default
        case 60..<80: return .accentColor
        default: return .secondary
        }
    }
    var body: some View {
        Text("\(score)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(color, in: Circle())
    }
}
