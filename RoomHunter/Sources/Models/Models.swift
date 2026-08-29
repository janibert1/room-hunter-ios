import Foundation

struct Candidate: Identifiable, Codable {
    let id: String
    let source: String
    let title: String
    let price: String?
    let location: String?
    let photos: [String]
    let rawText: String
    let score: Int
    let scoreBreakdown: [String: Int]?
    let scoredAt: String?

    enum CodingKeys: String, CodingKey {
        case id, source, title, price, location, photos
        case rawText = "raw_text"
        case score
        case scoreBreakdown = "score_breakdown"
        case scoredAt = "scored_at"
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
    let sentAt: String
    let status: HistoryStatus
    let lastStatusChange: String?

    enum CodingKeys: String, CodingKey {
        case id, source, title
        case sentAt = "sent_at"
        case status
        case lastStatusChange = "last_status_change"
    }
}
