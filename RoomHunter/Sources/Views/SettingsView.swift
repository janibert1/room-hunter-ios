import SwiftUI

/// Base URL / API key are editable here rather than hardcoded -- the backend
/// didn't have a stable public URL when this app was first built, and
/// fedora's home IP can change (see auto-memory project_infrastructure.md).
/// Point this at whatever the backend actually is (a local Tailscale
/// address, a public tunnel, whatever gets set up) without needing a
/// rebuild.
struct SettingsView: View {
    @ObservedObject var settings = APISettings.shared
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Base URL", text: $settings.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key", text: $settings.apiKey)
                }
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting { ProgressView() } else { Text("Test connection") }
                    }
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("ntfy") {
                    Text("Notifications arrive via ntfy (not Apple Push), since this app runs unsigned through LiveContainer. Tapping a notification opens roomhunter://candidate/{id}, which jumps straight to that listing here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    func testConnection() async {
        isTesting = true
        testResult = nil
        do {
            _ = try await APIClient(settings: settings).fetchCandidates()
            testResult = "✓ Connected"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
        isTesting = false
    }
}
