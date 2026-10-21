import Foundation

/// A calendar day without a time or time zone, such as the relationship start
/// or a countdown target (`YYYY-MM-DD`). Comparing two of them never depends on
/// the clock, daylight saving time, or the device time zone.
nonisolated struct LockScreenCalendarDate: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ raw: String) {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(containing date: Date, in calendar: Calendar) {
        let parts = Self.gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1_970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = Self(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid calendar date: \(raw)"
            )
        }
        self = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar. Subtracting two
    /// of these gives whole calendar days, with leap days counted and no time zone involved.
    var dayNumber: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    func days(until other: Self) -> Int {
        other.dayNumber - dayNumber
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    func startOfDay(in calendar: Calendar) -> Date? {
        Self.gregorian(like: calendar).date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The server's dates are Gregorian. A phone set to another calendar, such
    /// as the Buddhist one, would read 2026 as 2569, so only the time zone is
    /// taken from `calendar`.
    private static func gregorian(like calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}

/// What the Lock Screen and Home Screen widgets show, as `widget:get_lock_screen_state` returns it.
/// Dates named `*_on` are calendar days. Everything else is a moment in time.
nonisolated struct LockScreenSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var partner: Partner?
    var startedOn: LockScreenCalendarDate?
    /// Every countdown and both birthdays, for the Lock Screen and Home Screen countdown widgets.
    var dates: Dates
    var distance: Distance?
    var coupleDay: CoupleDay?
    var streak: Streak?
    var dailyQuestion: DailyQuestion?
    var games: Games

    struct Partner: Codable, Equatable, Sendable {
        /// What this person calls their partner, decided by the server: their nickname for the
        /// partner when they set one, otherwise the partner's own name.
        var name: String?
        /// True when `name` is the nickname.
        var usesNickname: Bool
        var timeZoneID: String?

        enum CodingKeys: String, CodingKey {
            case name
            case usesNickname = "uses_nickname"
            case timeZoneID = "time_zone_id"
        }

        /// The name for a small widget. A nickname shows whole. The partner's own name shows as its
        /// first word.
        var shortName: String? {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            if usesNickname {
                return name
            }
            return name.split(separator: " ").first.map(String.init)
        }
    }

    /// The couple's dates as stored. The widget works out the next time each one
    /// comes round from the phone's calendar (`LockScreenDates`).
    struct Dates: Codable, Equatable, Sendable {
        var countdowns: [DatedCountdown]
        var birthdays: [Birthday]
    }

    struct DatedCountdown: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        /// The day it counts down to. For a yearly countdown, the day it was first made for.
        var targetDate: LockScreenCalendarDate
        var repeatsYearly: Bool
        /// When it was made. The Lock Screen progress bar starts here for a one-off
        /// countdown and for the first year of a yearly one.
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case targetDate = "target_date"
            case repeatsYearly = "repeats_yearly"
            case createdAt = "created_at"
        }
    }

    struct Birthday: Codable, Equatable, Sendable {
        /// True for the person who owns this phone.
        var isMine: Bool
        /// The day they were born. Only the month and day are used.
        var birthday: LockScreenCalendarDate

        enum CodingKeys: String, CodingKey {
            case isMine = "is_mine"
            case birthday
        }
    }

    struct Distance: Codable, Equatable, Sendable {
        var meters: Double
        var asOf: Date

        enum CodingKeys: String, CodingKey {
            case meters
            case asOf = "as_of"
        }
    }

    /// The couple's current day. Day-based flags below reset when `endsAt` passes.
    struct CoupleDay: Codable, Equatable, Sendable {
        var localDate: String
        var startsAt: Date
        var endsAt: Date

        enum CodingKeys: String, CodingKey {
            case localDate = "local_date"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
        }
    }

    struct Streak: Codable, Equatable, Sendable {
        var currentCount: Int
        var meActiveToday: Bool
        var partnerActiveToday: Bool

        enum CodingKeys: String, CodingKey {
            case currentCount = "current_count"
            case meActiveToday = "me_active_today"
            case partnerActiveToday = "partner_active_today"
        }
    }

    struct DailyQuestion: Codable, Equatable, Sendable {
        var meAnswered: Bool
        var partnerAnswered: Bool

        enum CodingKeys: String, CodingKey {
            case meAnswered = "me_answered"
            case partnerAnswered = "partner_answered"
        }
    }

    struct Games: Codable, Equatable, Sendable {
        var myTurnCount: Int
        /// The game's `GameKind` raw value, such as `draw_and_guess`.
        var firstMyTurnKind: String?

        enum CodingKeys: String, CodingKey {
            case myTurnCount = "my_turn_count"
            case firstMyTurnKind = "first_my_turn_kind"
        }
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case partner
        case startedOn = "started_on"
        case dates
        case distance
        case coupleDay = "couple_day"
        case streak
        case dailyQuestion = "daily_question"
        case games
    }

    /// Reads the server's JSON. Timestamps may or may not carry fractional seconds.
    static func decode(_ data: Data) throws -> Self {
        try PaeoniaConvexClient.decoder.decode(Self.self, from: data)
    }

    /// False once the couple's day in the snapshot has ended. Flags such as
    /// "active today" and "answered" then no longer describe the new day.
    func isInCoupleDay(at date: Date) -> Bool {
        coupleDay.map { date < $0.endsAt } ?? true
    }
}

/// The arguments of `widget:get_lock_screen_state`. Convex queries cannot read
/// the clock, so the phone sends its time, rounded down to the whole minute.
nonisolated struct LockScreenStateRequest: Encodable, Equatable, Sendable {
    let now: Date

    init(now: Date) {
        self.now = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    enum CodingKeys: String, CodingKey {
        case now = "p_now"
    }
}

/// The file in the App Group that holds the last snapshot for the widgets.
nonisolated struct LockScreenCache: Codable, Equatable, Sendable {
    /// Relative to the App Group container.
    static let relativePath = "Widget/lock-screen.json"
    /// App Group defaults key. The app sets it before it reloads the widgets
    /// after a write, so a fetch that started earlier is not reused.
    static let invalidatedAtKey = "paeonia.lockScreen.invalidatedAt"

    var fetchedAt: Date
    var snapshot: LockScreenSnapshot

    enum CodingKeys: String, CodingKey {
        case fetchedAt = "fetched_at"
        case snapshot
    }

    func encoded() throws -> Data {
        try PaeoniaConvexClient.encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        try PaeoniaConvexClient.decoder.decode(Self.self, from: data)
    }
}

/// The Lock Screen widget kinds that read the snapshot. The app reloads these by kind.
nonisolated enum LockScreenWidgetKind {
    static let daysTogether = "PaeoniaDaysTogetherWidget"
    static let nextCountdown = "PaeoniaNextCountdownWidget"
    static let theirTime = "PaeoniaTheirTimeWidget"
    static let distance = "PaeoniaDistanceWidget"
    static let streak = "PaeoniaStreakWidget"
    static let dailyQuestion = "PaeoniaDailyQuestionWidget"
    static let yourMove = "PaeoniaYourMoveWidget"

    static let all = [daysTogether, nextCountdown, theirTime, distance, streak, dailyQuestion, yourMove]
}

/// The Home Screen widget kinds that read the same snapshot. The drawing widget
/// (`PaeoniaAppGroup.widgetKind`) has its own files.
nonisolated enum HomeScreenWidgetKind {
    static let daysTogether = "PaeoniaHomeDaysTogetherWidget"
    static let countdown = "PaeoniaHomeCountdownWidget"
    static let streak = "PaeoniaHomeStreakWidget"
    static let dailyQuestion = "PaeoniaHomeDailyQuestionWidget"

    static let all = [daysTogether, countdown, streak, dailyQuestion]
}

/// Every widget that reads the snapshot, on either screen. A reload, a push
/// token lookup or a privacy purge covers all of them.
nonisolated enum SnapshotWidgetKind {
    static let all = LockScreenWidgetKind.all + HomeScreenWidgetKind.all
}
