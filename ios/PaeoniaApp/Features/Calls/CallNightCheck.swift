import Foundation

/// Whether it is night where the partner is, so the app asks before it rings. The hours are the
/// night that quiet pushes use (`QUIET_NIGHT_START_HOUR` and `QUIET_NIGHT_END_HOUR` in
/// `backend/convex/lib/apns.ts`): from 22:00 until 07:00 on the partner's clock.
nonisolated enum CallNightCheck {
    static let startHour = 22
    static let endHour = 7

    static func isNight(at date: Date, in timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return hour >= startHour || hour < endHour
    }

    /// The partner's clock, such as "02:14", in the person's own locale.
    static func localTime(at date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
