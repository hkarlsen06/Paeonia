import Foundation

nonisolated struct AnniversaryRecap: Codable, Equatable, Identifiable, Sendable {
    nonisolated struct Counts: Codable, Equatable, Sendable {
        let answeredTogether: Int
        let drawings: Int
        let memories: Int
        let memoryPhotos: Int
        let stories: Int
        let letters: Int
        let visits: Int
        let visitDays: Int
        let gameDays: Int
        let heartsAllTime: Int
        let longestStreakAllTime: Int

        enum CodingKeys: String, CodingKey {
            case answeredTogether = "answered_together"
            case drawings
            case memories
            case memoryPhotos = "memory_photos"
            case stories
            case letters
            case visits
            case visitDays = "visit_days"
            case gameDays = "game_days"
            case heartsAllTime = "hearts_all_time"
            case longestStreakAllTime = "longest_streak_all_time"
        }
    }

    let anniversaryDate: String
    let years: Int
    let periodStart: String
    let periodEnd: String
    let sinceJoined: Bool
    /// The couple-local day the all-time numbers were read.
    let countedOn: String
    let counts: Counts

    var id: String { anniversaryDate }

    enum CodingKeys: String, CodingKey {
        case anniversaryDate = "anniversary_date"
        case years
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case sinceJoined = "since_joined"
        case countedOn = "counted_on"
        case counts
    }

    static let shownDays = 14

    func isShown(today: String) -> Bool {
        guard let days = RecapCalendar.days(from: anniversaryDate, to: today) else { return false }
        return days >= 0 && days < Self.shownDays
    }
}

nonisolated enum RecapCalendar {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func today(_ now: Date, in timeZone: TimeZone = .current) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: now)
        return format(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func latestAnniversary(startedOn: String, today: String) -> String? {
        guard let start = parts(startedOn), let startYear = start.year, let month = start.month, let day = start.day,
              let thisYear = parts(today)?.year
        else { return nil }
        for year in [thisYear, thisYear - 1] where year > startYear {
            let candidate = format(year: year, month: month, day: min(day, daysInMonth(year, month)))
            if candidate <= today { return candidate }
        }
        return nil
    }

    static func days(from: String, to: String) -> Int? {
        guard let start = date(from), let end = date(to) else { return nil }
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    static func displayDate(_ day: String) -> Date? {
        guard let parts = parts(day) else { return nil }
        return Calendar(identifier: .gregorian).date(from: parts)
    }

    private static func date(_ day: String) -> Date? {
        guard let parts = parts(day) else { return nil }
        return calendar.date(from: parts)
    }

    private static func parts(_ day: String) -> DateComponents? {
        let values = day.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return DateComponents(year: values[0], month: values[1], day: values[2])
    }

    private static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        guard let date = calendar.date(from: DateComponents(year: year, month: month)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 28 }
        return range.count
    }

    private static func format(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
