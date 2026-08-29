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
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.accent)
                        Text(errorMessage).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 44))
                            .foregroundStyle(.accent)
                        Text("Nothing sent yet").font(.headline).foregroundStyle(.secondary)
                        Text("Rooms you respond to show up here").font(.subheadline).foregroundStyle(.tertiary)
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
        case .replied: return Color(red: 0.29, green: 0.60, blue: 0.36)
        case .sent: return .accentColor
        case .noReplyYet: return .secondary
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
