import SwiftUI

struct HistoryView: View {
    @State private var items: [HistoryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    let api = APIClient()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading…")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.secondary)
                        Button("Retry") { Task { await load() } }
                    }
                } else if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Nothing sent yet").foregroundStyle(.secondary)
                    }
                } else {
                    List(items) { item in
                        HistoryRow(item: item)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("History")
            .task { await load() }
        }
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
        case .replied: return .green
        case .sent: return .blue
        case .noReplyYet: return .gray
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
                if let change = item.lastStatusChange {
                    Text(change).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
