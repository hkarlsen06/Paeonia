import Foundation

/// Where a letter is (`backend/convex/lib/letters.ts`). The recipient's phone never gets a
/// sealed letter, and gets a delivered one without its note and photo until it is opened.
nonisolated enum LetterState: String, Codable, Sendable {
    case sealed
    case delivered
    case opened
}

/// When a letter arrives. Only the author's phone knows it.
nonisolated enum LetterDeliveryKind: String, Codable, Sendable {
    case now
    case at
    case morning
}

/// One letter as the server shows it to this person (`letters:get_letters`).
nonisolated struct Letter: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let authorUserID: UUID
    let recipientUserID: UUID
    let templateKey: LetterTemplate.Key
    /// Nil on a letter this person received and has not opened.
    let body: String?
    let mediaAssetID: UUID?
    let deliveryKind: LetterDeliveryKind?
    let deliverAt: Date?
    var state: LetterState
    let deliveredAt: Date?
    var openedAt: Date?
    let createdAt: Date

    /// The longest note the composer takes, in characters. The server counts code points.
    static let maxBodyLength = 2_000

    enum CodingKeys: String, CodingKey {
        case id
        case authorUserID = "author_user_id"
        case recipientUserID = "recipient_user_id"
        case templateKey = "template_key"
        case body
        case mediaAssetID = "media_asset_id"
        case deliveryKind = "delivery_kind"
        case deliverAt = "deliver_at"
        case state
        case deliveredAt = "delivered_at"
        case openedAt = "opened_at"
        case createdAt = "created_at"
    }
}

/// The couple's letters as this phone knows them, newest first, and the time zone the
/// partner's morning letters follow.
nonisolated struct MailSnapshot: Codable, Equatable, Sendable {
    var letters: [Letter] = []
    var partnerTimeZoneID: String?
}

/// The result of `letters:get_letters`.
nonisolated struct RemoteLetters: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let partnerTimeZoneID: String?
    let letters: [Letter]

    var snapshot: MailSnapshot {
        MailSnapshot(letters: letters, partnerTimeZoneID: partnerTimeZoneID)
    }

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case partnerTimeZoneID = "partner_time_zone_id"
        case letters
    }
}

/// Which letters show where, so the views, the badge and the tests share one rule.
nonisolated enum MailTimeline {
    static func received(_ letters: [Letter], by userID: UUID?) -> [Letter] {
        letters.filter { $0.recipientUserID == userID }
    }

    static func sent(_ letters: [Letter], by userID: UUID?) -> [Letter] {
        letters.filter { $0.authorUserID == userID }
    }

    /// Letters that arrived for this person and wait to be opened, oldest first.
    static func waiting(_ letters: [Letter], for userID: UUID?) -> [Letter] {
        received(letters, by: userID)
            .filter { $0.state == .delivered }
            .sorted { ($0.deliveredAt ?? $0.createdAt) < ($1.deliveredAt ?? $1.createdAt) }
    }
}

/// When a letter is set to arrive, as the composer offers it.
nonisolated enum LetterDelivery: Codable, Equatable, Sendable {
    case now
    case morning
    case at(Date)

    var kind: LetterDeliveryKind {
        switch self {
        case .now: .now
        case .morning: .morning
        case .at: .at
        }
    }

    /// The next 08:00 in `timeZone` after `now`, which is when the server delivers a morning letter.
    static func nextMorning(after now: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
