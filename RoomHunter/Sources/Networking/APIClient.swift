import Foundation

/// Base URL + API key are configurable at runtime (Settings tab), not hardcoded
/// -- the backend server didn't have a real reachable URL/key yet when this app
/// was first built (2026-08-29), and even once it does, fedora's URL can change
/// (dynamic home IP, see auto-memory project_infrastructure.md's IP-change
/// procedure) so this needs to stay editable rather than baked in.
final class APISettings: ObservableObject {
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "api_base_url") }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "api_key") }
    }

    static let shared = APISettings()

    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: "api_base_url") ?? "http://127.0.0.1:8020"
        self.apiKey = UserDefaults.standard.string(forKey: "api_key") ?? ""
    }
}

enum APIError: Error, LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad server URL — check Settings."
        case .http(let code, let body): return "Server error \(code): \(body)"
        case .decoding(let e): return "Couldn't read the server's response: \(e.localizedDescription)"
        }
    }
}

/// Thin wrapper around the room-hunter backend API. Every call is a plain
/// async function returning a decoded model or throwing APIError -- no
/// caching/retry logic here on purpose, callers (the views) own their own
/// loading/error state so failures are always visible, not silently retried
/// into staleness for something Jan is about to make a real decision on.
struct APIClient {
    let settings: APISettings

    init(settings: APISettings = .shared) {
        self.settings = settings
    }

    /// `URL(string:)` fails outright (returns nil) on a trailing space or
    /// newline in the host portion -- confirmed live 2026-08-29: a plain
    /// TextField-entered base URL picked up a trailing space (iOS keyboards
    /// do this on dismiss/autocomplete-bar interaction even with
    /// autocorrectionDisabled(), which only suppresses autocorrect
    /// substitution, not the QuickType bar's own space-insertion behavior)
    /// and silently broke every request with "Bad server URL" despite the
    /// URL looking completely normal in Settings. Also strips a trailing
    /// slash so "https://host/" and "https://host" both concatenate with
    /// a leading-slash path ("/candidates") the same correct way, instead
    /// of one of them producing a double slash.
    private var normalizedBaseURL: String {
        var s = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: normalizedBaseURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !settings.apiKey.isEmpty {
            req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(0, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func fetchCandidates() async throws -> [Candidate] {
        let data = try await request("/candidates")
        do { return try JSONDecoder().decode([Candidate].self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func sendDecision(candidateId: String, decision: Bool) async throws {
        let body = try JSONEncoder().encode(["decision": decision ? "yes" : "no"])
        _ = try await request("/candidates/\(candidateId)/decision", method: "POST", body: body)
    }

    func fetchDraft(candidateId: String) async throws -> Draft {
        let data = try await request("/candidates/\(candidateId)/draft")
        do { return try JSONDecoder().decode(Draft.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func saveDraftEdit(candidateId: String, editedText: String) async throws {
        let body = try JSONEncoder().encode(["edited_text": editedText])
        _ = try await request("/candidates/\(candidateId)/draft", method: "POST", body: body)
    }

    /// The real live-send action -- this is the one call in the whole app
    /// that actually reaches a real stranger. Every call site of this
    /// function must go through an explicit confirmation step first (see
    /// DraftReviewView) -- never call this from a single tap alone.
    func sendMessage(candidateId: String) async throws {
        _ = try await request("/candidates/\(candidateId)/send", method: "POST")
    }

    func fetchHistory() async throws -> [HistoryItem] {
        let data = try await request("/history")
        do { return try JSONDecoder().decode([HistoryItem].self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
