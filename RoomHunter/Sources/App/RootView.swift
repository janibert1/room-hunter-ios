import SwiftUI

/// Root tab bar + the deep-link entry point. ntfy notifications carry a
/// click URL of the form roomhunter://candidate/{id} (configured server-side
/// when a notification is published) -- when the OS hands that URL to us
/// (via the ntfy app's own real push, since this app can't hold a genuine
/// APNs entitlement unsigned), we route straight to that candidate in the
/// Queue tab rather than making Jan hunt for it.
struct RootView: View {
    @State private var selectedTab = 0
    @StateObject private var nav = NavigationCoordinator()

    var body: some View {
        TabView(selection: $selectedTab) {
            CandidateQueueView()
                .tabItem { Label("Queue", systemImage: "house.and.flag") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .tint(.accentColor)
        .environmentObject(nav)
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // roomhunter://candidate/{id}
        guard url.scheme == "roomhunter", url.host == "candidate" else { return }
        let id = url.pathComponents.filter { $0 != "/" }.first ?? url.lastPathComponent
        guard !id.isEmpty else { return }
        selectedTab = 0
        nav.pendingCandidateId = id
    }
}
