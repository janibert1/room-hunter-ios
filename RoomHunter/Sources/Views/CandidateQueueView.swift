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
            Group {
                if isLoading && candidates.isEmpty {
                    ProgressView("Loading…")
                } else if let errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.accent)
                        Text(errorMessage).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if candidates.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.accent)
                        Text("Nothing waiting on you").font(.headline).foregroundStyle(.secondary)
                        Text("New rooms will show up here").font(.subheadline).foregroundStyle(.tertiary)
                    }
                } else {
                    List(candidates) { candidate in
                        Button { selected = candidate } label: {
                            CandidateRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
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
                    if let price = candidate.price {
                        Text(price).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let location = candidate.location {
                        Text("· \(location)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text(candidate.source).font(.caption2).textCase(.uppercase).foregroundStyle(.tertiary)
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
