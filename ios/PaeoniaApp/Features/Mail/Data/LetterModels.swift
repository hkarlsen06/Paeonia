import Foundation

/// Where a letter is (`backend/convex/lib/letters.ts`). The recipient's phone never gets a
/// sealed letter, and gets a delivered one without its note and photo until it is opened.
nonisolated enum LetterState: String, Codable, Sendable {
    case sealed
    case delivered
    case opened
}

/// When a letter arrives. Only the author's phone knows it. A `together` letter has no time and
/// arrives when the partners next meet.
nonisolated enum LetterDeliveryKind: String, Codable, Sendable {
    case now
    case at
    case morning
    case together
}

/// One letter as the server shows it to this person (`letters:get_letters`).
nonisolated struct Letter: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let authorUserID: UUID
    let recipientUserID: UUID
    /// Nil on a letter this person received and has not opened.
    let templateKey: LetterTemplate.Key?
    /// Nil on a letter this person received and has not opened.
    let body: String?
    let mediaAssetID: UUID?
    let deliveryKind: LetterDeliveryKind?
    let deliverAt: Date?
    var state: LetterState
    let deliveredAt: Date?
    var openedAt: Date?
    /// When it was written. Nil on a letter this person received and has not opened.
    let createdAt: Date?

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

/// The two lists of the mailbox. The server names them `received` and `sent`.
nonisolated enum MailboxTab: String, Codable, Hashable, Sendable {
    case received
    case sent
}

/// Where a mailbox list goes on, which is the last letter of a page as the server gave it.
nonisolated struct LetterCursor: Codable, Equatable, Sendable {
    let at: String
    let id: UUID
}

/// Letters of one mailbox list, newest first, and where the older ones start.
nonisolated struct MailPage: Codable, Equatable, Sendable {
    var letters: [Letter] = []
    /// Nil when no older letters exist.
    var nextBefore: LetterCursor?

    enum CodingKeys: String, CodingKey {
        case letters
        case nextBefore = "next_before"
    }
}

/// This person's Mail as the server last sent it, with the letters waiting to be opened
/// (oldest first) and the newest page of each list. It is the result of `letters:get_letters`
/// and what this phone stores. Older pages stay in memory while the mailbox is open.
nonisolated struct MailSnapshot: Codable, Equatable, Sendable {
    var waiting: [Letter] = []
    var received = MailPage()
    var sent = MailPage()

    subscript(tab: MailboxTab) -> MailPage {
        get { tab == .received ? received : sent }
        set {
            if tab == .received { received = newValue } else { sent = newValue }
        }
    }

    /// Every letter the snapshot holds, each once.
    var letters: [Letter] {
        var seen = Set<UUID>()
        return (waiting + received.letters + sent.letters).filter { seen.insert($0.id).inserted }
    }
}

/// Which letters show where, so the views, the badge and the tests share one rule.
nonisolated enum MailTimeline {
    /// The order of a list. Received letters go by when they arrived, sent ones by when they
    /// were written, then by id, as the server pages them.
    static func precedes(_ lhs: Letter, _ rhs: Letter, in tab: MailboxTab) -> Bool {
        let left = sortDate(lhs, in: tab), right = sortDate(rhs, in: tab)
        if left != right { return left > right }
        return lhs.id.uuidString.lowercased() > rhs.id.uuidString.lowercased()
    }

    private static func sortDate(_ letter: Letter, in tab: MailboxTab) -> Date {
        (tab == .received ? letter.deliveredAt : letter.createdAt) ?? .distantPast
    }

    /// The server's newest page followed by the older letters this phone already had after
    /// it, so loading older letters goes on where `known` ended. A page that shares no letter
    /// with `known` means more than a page arrived since, and keeping the older letters would
    /// leave a hole, so the list starts again from the page.
    static func merged(_ page: MailPage, keeping known: MailPage, in tab: MailboxTab) -> MailPage {
        guard page.nextBefore != nil, let end = page.letters.last else { return page }
        let pageIDs = Set(page.letters.map(\.id))
        guard known.letters.contains(where: { pageIDs.contains($0.id) }) else { return page }
        let older = known.letters.filter { !pageIDs.contains($0.id) && precedes(end, $0, in: tab) }
        guard !older.isEmpty else { return page }
        return MailPage(letters: page.letters + older, nextBefore: known.nextBefore)
    }

    /// Letters that arrived for this person and wait to be opened, oldest first.
    static func waiting(_ letters: [Letter], for userID: UUID?) -> [Letter] {
        letters
            .filter { $0.recipientUserID == userID && $0.state == .delivered }
            .sorted { ($0.deliveredAt ?? .distantPast) < ($1.deliveredAt ?? .distantPast) }
    }
}

/// When a letter is set to arrive, as the composer offers it.
nonisolated enum LetterDelivery: Codable, Equatable, Sendable {
    case now
    case morning
    case at(Date)
    case together

    var kind: LetterDeliveryKind {
        switch self {
        case .now: .now
        case .morning: .morning
        case .at: .at
        case .together: .together
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

/// What the composer's delivery step offers, as `letters:get_letter_delivery_options` read it
/// when the composer opened.
nonisolated struct MailDeliveryOptions: Decodable, Equatable, Sendable {
    /// The zone the partner's morning letters follow. Nil without a partner.
    var partnerTimeZoneID: String?
    var togetherNow = false
    /// The first day of the next visit (`yyyy-MM-dd`) that starts after today, when a letter
    /// written now would arrive on its evening.
    var nextVisitStartDate: String?
    /// The next visit starts too soon for a letter written now to arrive on its evening.
    var nextVisitTooSoon = false
    var bothShareLocation = false

    enum CodingKeys: String, CodingKey {
        case partnerTimeZoneID = "partner_time_zone_id"
        case togetherNow = "together_now"
        case nextVisitStartDate = "next_visit_start_date"
        case nextVisitTooSoon = "next_visit_too_soon"
        case bothShareLocation = "both_share_location"
    }

    /// How a letter for the next meeting would arrive, or why it can't be sent now.
    enum NextMeeting: Equatable, Sendable {
        /// At the visit that starts on `start`, or sooner when the phone shows the partners
        /// together and `byLocation` holds.
        case visit(start: Date, byLocation: Bool)
        /// When the phone shows the partners together.
        case location
        /// The partners are together today, so the next meeting is not this one.
        case togetherNow
        /// The next visit starts too soon to wait for, and location can't tell.
        case visitTooSoon
        /// No visit is planned and location can't tell.
        case unplanned

        var offersLetter: Bool {
            switch self {
            case .visit, .location: true
            case .togetherNow, .visitTooSoon, .unplanned: false
            }
        }
    }

    /// False while a draft that chose the next meeting can't be sent with that choice.
    func allows(_ delivery: LetterDelivery) -> Bool {
        delivery != .together || nextMeeting().offersLetter
    }

    func nextMeeting(calendar: Calendar = .current) -> NextMeeting {
        if togetherNow { return .togetherNow }
        if let start = nextVisitStartDate.flatMap(LockScreenCalendarDate.init)?.startOfDay(in: calendar) {
            return .visit(start: start, byLocation: bothShareLocation)
        }
        if bothShareLocation { return .location }
        return nextVisitTooSoon ? .visitTooSoon : .unplanned
    }
}
