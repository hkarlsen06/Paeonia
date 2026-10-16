import Foundation

/// The "Their time" widget: the partner's clock, read from their time zone.
nonisolated struct LockScreenPartnerClock: Equatable, Sendable {
    /// How far the partner's clock is from this phone's clock.
    enum Offset: Equatable, Sendable {
        case same
        case ahead(minutes: Int)
        case behind(minutes: Int)
    }

    /// Entries the timeline holds, one per minute. Entries are free and each
    /// reload costs budget, so six hours means four reloads a day.
    static let timelineMinutes = 6 * 60
    /// The sun shows from 06:00 to 19:59 partner time, the moon the rest of the day.
    static let daytimeHours = 6..<20

    let timeZone: TimeZone

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    init?(timeZoneID: String?) {
        guard let timeZoneID, let timeZone = TimeZone(identifier: timeZoneID) else { return nil }
        self.timeZone = timeZone
    }

    func hourAndMinute(at date: Date) -> (hour: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The partner's time of day as text, such as "01:30" or "1:30 AM", in `locale`'s style.
    /// `.shortened` writes "1:30" in 24-hour locales such as Norwegian, where the
    /// Lock Screen clock says "01:30", so those get two-digit hours.
    func timeText(at date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let hourPattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone)
        return hourPattern.contains("a")
            ? date.formatted(style.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
            : date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// Clockwise degrees from 12 o'clock. The hour hand moves with the minutes.
    func hourHandDegrees(at date: Date) -> Double {
        let time = hourAndMinute(at: date)
        return (Double(time.hour % 12) + Double(time.minute) / 60) * 30
    }

    func minuteHandDegrees(at date: Date) -> Double {
        Double(hourAndMinute(at: date).minute) * 6
    }

    func isDaytime(at date: Date) -> Bool {
        Self.daytimeHours.contains(hourAndMinute(at: date).hour)
    }

    /// The gap at `date`. Daylight saving time changes it, so it depends on the date.
    func offset(at date: Date, from local: TimeZone) -> Offset {
        let seconds = timeZone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes > 0 { return .ahead(minutes: minutes) }
        if minutes < 0 { return .behind(minutes: -minutes) }
        return .same
    }

    /// Start of the minute `date` is in, then one date per minute after it.
    static func minuteEntryDates(from date: Date, count: Int = timelineMinutes) -> [Date] {
        let start = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return (0..<count).map { Date(timeIntervalSinceReferenceDate: start + Double($0) * 60) }
    }
}
