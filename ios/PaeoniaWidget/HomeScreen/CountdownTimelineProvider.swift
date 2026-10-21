#if WIDGET_EXTENSION
import WidgetKit

/// What the countdown widget renders at one moment: the shared snapshot and the
/// date the person picked in the widget's settings (nil for "Next one").
struct CountdownEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: LockScreenSnapshot?
    let choiceID: String?
}

/// The same timeline as the other snapshot widgets (`LockScreenTimelineProvider`,
/// a new entry at every midnight and when the couple's day ends), with the
/// person's choice added to each entry.
struct CountdownTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, snapshot: .sample(now: .now), choiceID: nil)
    }

    // `AppIntentTimelineProvider` requires this to be async, but nothing here waits.
    // swiftlint:disable:next async_without_await
    func snapshot(for configuration: CountdownWidgetIntent, in context: Context) async -> CountdownEntry {
        let snapshot = context.isPreview
            ? LockScreenSnapshot.sample(now: .now)
            : LockScreenStateService.loadCache()?.snapshot
        return CountdownEntry(date: .now, snapshot: snapshot, choiceID: configuration.date?.id)
    }

    func timeline(for configuration: CountdownWidgetIntent, in context: Context) async -> Timeline<CountdownEntry> {
        await LockScreenStateService.refreshWithinDeadline()
        let snapshot = LockScreenStateService.loadCache()?.snapshot
        let base = LockScreenTimelineProvider.timeline(for: snapshot, schedule: .daily, now: .now)
        return Timeline(
            entries: base.entries.map {
                CountdownEntry(date: $0.date, snapshot: $0.snapshot, choiceID: configuration.date?.id)
            },
            policy: base.policy
        )
    }
}
#endif
