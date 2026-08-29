import Foundation

/// Shared across the tab bar so the deep-link handler (RootView) can tell
/// CandidateQueueView "open this specific candidate" without needing a
/// direct reference into that view's own @State -- SwiftUI views are value
/// types, so a separately-held instance's @State is disconnected from
/// whatever SwiftUI is actually rendering; an ObservableObject in the
/// environment is the correct way to reach across the tab hierarchy.
final class NavigationCoordinator: ObservableObject {
    @Published var pendingCandidateId: String?
}
