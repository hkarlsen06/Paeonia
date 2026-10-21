#if WIDGET_EXTENSION
import WidgetKit

/// What one widget that reads the snapshot renders at one moment. A nil snapshot means
/// signed out, not paired, or nothing saved yet, and shows the neutral state.
struct LockScreenEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: LockScreenSnapshot?
}

/// Feeds every Lock Screen widget and the Home Screen ones that read the snapshot.
/// They differ only in how often the picture changes by itself.
struct LockScreenTimelineProvider: TimelineProvider {
    enum Schedule {
        /// Values change at midnight and when the couple's day ends.
        case daily
        /// The partner's clock: one entry per minute for the next six hours.
        case everyMinute
    }

    let schedule: Schedule

    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: .now, snapshot: .sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        let snapshot = context.isPreview
            ? LockScreenSnapshot.sample(now: .now)
            : LockScreenStateService.loadCache()?.snapshot
        completion(LockScreenEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LockScreenEntry>) -> Void) {
        Task {
            await LockScreenStateService.refreshWithinDeadline()
            let snapshot = LockScreenStateService.loadCache()?.snapshot
            completion(Self.timeline(for: snapshot, schedule: schedule, now: .now))
        }
    }

    static func timeline(
        for snapshot: LockScreenSnapshot?,
        schedule: Schedule,
        now: Date,
        calendar: Calendar = .current
    ) -> Timeline<LockScreenEntry> {
        let hasPartnerClock = LockScreenPartnerClock(timeZoneID: snapshot?.partner?.timeZoneID) != nil
        if schedule == .everyMinute, hasPartnerClock {
            return Timeline(
                entries: LockScreenPartnerClock.minuteEntryDates(from: now).map {
                    LockScreenEntry(date: $0, snapshot: snapshot)
                },
                policy: .atEnd
            )
        }
        let dates = LockScreenTimeline.entryDates(for: snapshot, now: now, calendar: calendar)
        return Timeline(
            entries: dates.map { LockScreenEntry(date: $0, snapshot: snapshot) },
            policy: .after(LockScreenTimeline.reloadDate(for: snapshot, entryDates: dates, now: now))
        )
    }
}
#endif
