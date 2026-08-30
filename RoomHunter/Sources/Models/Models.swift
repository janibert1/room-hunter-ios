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
    // 2026-08-30, Jan asked for "how long since the room was placed on
    // Kamernet" in the app. Raw ISO string from the source (Kamernet's
    // publishDate/createDate, Laga's WhatsApp message timestamp) -- NOT
    // pre-formatted server-side, same reasoning as HistoryItem.sentAt/
    // lastStatusChange: compute the relative label client-side so it
    // stays correct without a re-fetch. nil for a source with no real
    // posted date (Room.nl -- doesn't reach /candidates at all anyway).
    let postedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, source, title, price, location, photos
        case rawText = "raw_text"
        case score
        case scoreBreakdown = "score_breakdown"
        case scoredAt = "scored_at"
        case postedAt = "posted_at"
    }

    /// "€695/month", or nil if price is unknown -- callers should treat
    /// nil the same way they already treat a nil price (just don't show
    /// a price line), same as before this was still a String.
    var formattedPrice: String? {
        price.map { "€\($0)/month" }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    // Two real formats seen live in production data, neither of which
    // ISO8601DateFormatter's default options parse on their own: Laga's
    // "2026-08-16T13:51:46.000Z" (fractional seconds + Z) and Kamernet's
    // "2026-08-29T12:17:34.017" (fractional seconds, no timezone
    // designator at all -- Kamernet's own API just omits it). Try the
    // strict internet-date-time+fractional-seconds parser first (handles
    // Laga), then fall back to a fixed-format DateFormatter with no
    // timezone assumption beyond "treat it as UTC", which is fine here --
    // this only ever feeds a coarse "N days ago" label, a few hours of
    // slop from an unstated timezone doesn't matter.
    private static let strictISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let noTimezoneFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    static func parsePostedAt(_ raw: String) -> Date? {
        strictISOFormatter.date(from: raw) ?? noTimezoneFormatter.date(from: raw)
    }

    /// "3 days ago", or nil if postedAt is missing/unparseable -- callers
    /// should just omit the line in that case, same as every other
    /// optional display field on this model.
    var postedAtRelative: String? {
        guard let postedAt, let date = Self.parsePostedAt(postedAt) else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 2026-08-30, Jan's explicit ask: "preview the photo that i send and
/// allow me to change them" -- one of Jan's own profile photos (always
/// attached to a real send, see profile_photos.py server-side), shown in
/// DraftReviewView with a toggle so he can pick which ones actually go
/// out before sending, not just discover after the fact that it always
/// sent all of them.
struct ProfilePhoto: Identifiable, Codable {
    let id: Int
    let url: String
    let selected: Bool
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
    // Added 2026-08-29: Jan wants a real record for the two other things
    // that can happen to a listing besides "sent" -- he declined it
    // himself (Kamernet/Laga "No"), or Room.nl's is_eligible() skipped it
    // automatically (a demolition/renovation-permit-restricted listing).
    // Neither implies a message ever went out, so neither reuses sent/
    // replied/noReplyYet -- those all read as "something was sent, we're
    // waiting" which would be misleading here.
    case declined
    case ineligible

    var label: String {
        switch self {
        case .sent: return "Sent"
        case .replied: return "Replied"
        case .noReplyYet: return "No reply yet"
        case .declined: return "Declined"
        case .ineligible: return "Skipped — not eligible"
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
