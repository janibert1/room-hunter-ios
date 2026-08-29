import Foundation

struct Candidate: Identifiable, Codable {
    let id: String
    let source: String
    let title: String
    // Confirmed live against the real API 2026-08-29: this is a plain
    // number (euros/month, from extractor.py's price_eur_monthly), not a
    // formatted string -- decoding as String here made every real
    // candidate (anything with a real price, i.e. all of them) fail with
    // "the data couldn't be read because it isn't in the correct format",
    // which only showed up once real backfilled data existed (an empty
    // [] response, the only thing tested before, has nothing to trip
    // this on).
    let price: Int?
    let location: String?
    let photos: [String]
    let rawText: String
    let score: Int
    let scoreBreakdown: [String: Int]?
    // Same real bug as price -- store.py/main.py write this via Python's
    // time.time() (a Unix timestamp float), not a formatted string.
    let scoredAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, source, title, price, location, photos
        case rawText = "raw_text"
        case score
        case scoreBreakdown = "score_breakdown"
        case scoredAt = "scored_at"
    }

    /// "€695/month", or nil if price is unknown -- callers should treat
    /// nil the same way they already treat a nil price (just don't show
    /// a price line), same as before this was still a String.
    var formattedPrice: String? {
        price.map { "€\($0)/month" }
    }
}

struct HighlightSpan: Codable {
    let start: Int
    let end: Int
}

struct Draft: Codable {
    let fullText: String
    let highlightedSpans: [HighlightSpan]

    enum CodingKeys: String, CodingKey {
        case fullText = "full_text"
        case highlightedSpans = "highlighted_spans"
    }
}

enum HistoryStatus: String, Codable {
    case sent
    case replied
    case noReplyYet = "no_reply_yet"

    var label: String {
        switch self {
        case .sent: return "Sent"
        case .replied: return "Replied"
        case .noReplyYet: return "No reply yet"
        }
    }
}

struct HistoryItem: Identifiable, Codable {
    let id: String
    let source: String
    let title: String
    // store.py writes both of these via Python's time.time() (a Unix
    // timestamp float) -- same real decoding bug as Candidate.price/
    // scoredAt above, fixed the same way (match the real type instead of
    // assuming a formatted string).
    let sentAt: Double
    let status: HistoryStatus
    let lastStatusChange: Double?

    enum CodingKeys: String, CodingKey {
        case id, source, title
        case sentAt = "sent_at"
        case status
        case lastStatusChange = "last_status_change"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var lastStatusChangeRelative: String? {
        lastStatusChange.map {
            Self.relativeFormatter.localizedString(for: Date(timeIntervalSince1970: $0), relativeTo: Date())
        }
    }
}
