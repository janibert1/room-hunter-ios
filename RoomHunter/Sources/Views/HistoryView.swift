import SwiftUI

struct HistoryView: View {
    @State private var items: [HistoryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    let api = APIClient()

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("History")
            .task { await load() }
        }
    }

    // Same fix as CandidateQueueView -- see its comment on `content`.
    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView("Loading…")
        } else if let errorMessage {
            errorState(errorMessage)
        } else if items.isEmpty {
            emptyState
        } else {
            historyList
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
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Nothing sent yet").font(.headline).foregroundStyle(.secondary)
            Text("Rooms you respond to show up here").font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    private var historyList: some View {
        List(items) { item in
            HistoryRow(item: item)
        }
        .listStyle(.plain)
        .refreshable { await load() }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            // Newest first -- server order isn't guaranteed, sort defensively.
            items = try await api.fetchHistory().sorted { $0.sentAt > $1.sentAt }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct HistoryRow: View {
    let item: HistoryItem

    var statusColor: Color {
        switch item.status {
        case .replied: return Color(red: 0.29, green: 0.60, blue: 0.36)
        case .sent: return .accentColor
        case .noReplyYet: return .secondary
        // Deliberately distinct from .secondary/.noReplyYet -- these two
        // are NOT "waiting to hear back", so they shouldn't read the same
        // way at a glance.
        case .declined: return Color(red: 0.72, green: 0.30, blue: 0.30)
        case .ineligible: return Color(red: 0.55, green: 0.45, blue: 0.68)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(item.source.uppercased()).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.status.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
                if let change = item.lastStatusChangeRelative {
                    Text(change).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
