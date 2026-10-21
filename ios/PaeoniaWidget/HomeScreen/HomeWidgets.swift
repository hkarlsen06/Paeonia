#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

// Four Home Screen widgets that read the snapshot the Lock Screen widgets use
// (`LockScreenStateService`), so they refresh with the same widget pushes, the
// same reloads from the app, and the same midnight entries. The drawing widget
// (`PaeoniaWidget`) has its own files.

struct DaysTogetherHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: HomeScreenWidgetKind.daysTogether,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            DaysTogetherHomeView(entry: entry)
                .containerBackground(.paeoniaWidgetBackground, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenDaysTogetherName))
        .description(String(localized: .widgetLockScreenDaysTogetherDescription))
        .supportedFamilies([.systemSmall, .systemMedium])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct CountdownHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: HomeScreenWidgetKind.countdown,
            intent: CountdownWidgetIntent.self,
            provider: CountdownTimelineProvider()
        ) { entry in
            CountdownHomeView(entry: entry)
                .containerBackground(.paeoniaWidgetBackground, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetHomeCountdownName))
        .description(String(localized: .widgetHomeCountdownDescription))
        .supportedFamilies([.systemSmall, .systemMedium])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct StreakHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: HomeScreenWidgetKind.streak,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            StreakHomeView(entry: entry)
                .containerBackground(.paeoniaWidgetBackground, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenStreakName))
        .description(String(localized: .widgetLockScreenStreakDescription))
        .supportedFamilies([.systemSmall])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct DailyQuestionHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: HomeScreenWidgetKind.dailyQuestion,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            DailyQuestionHomeView(entry: entry)
                .containerBackground(.paeoniaWidgetBackground, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenQuestionName))
        .description(String(localized: .widgetLockScreenQuestionDescription))
        .supportedFamilies([.systemSmall, .systemMedium])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

private extension LockScreenEntry {
    static var sample: LockScreenEntry { LockScreenEntry(date: .now, snapshot: .sample(now: .now)) }
    static var empty: LockScreenEntry { LockScreenEntry(date: .now, snapshot: nil) }
    /// Signed in and paired, with nothing set up yet.
    static var fresh: LockScreenEntry {
        var snapshot = LockScreenSnapshot.sample(now: .now)
        snapshot.startedOn = nil
        snapshot.dates = .init(countdowns: [], birthdays: [])
        snapshot.streak = .init(currentCount: 0, meActiveToday: false, partnerActiveToday: false)
        snapshot.dailyQuestion = .init(meAnswered: false, partnerAnswered: false)
        return LockScreenEntry(date: .now, snapshot: snapshot)
    }
}

private extension CountdownEntry {
    static var sample: CountdownEntry { CountdownEntry(date: .now, snapshot: .sample(now: .now), choiceID: nil) }
    static var oneDate: CountdownEntry {
        var snapshot = LockScreenSnapshot.sample(now: .now)
        snapshot.dates.countdowns.removeLast()
        snapshot.dates.birthdays = []
        return CountdownEntry(date: .now, snapshot: snapshot, choiceID: nil)
    }
    static var empty: CountdownEntry { CountdownEntry(date: .now, snapshot: nil, choiceID: nil) }
    static var fresh: CountdownEntry {
        var snapshot = LockScreenSnapshot.sample(now: .now)
        snapshot.dates = .init(countdowns: [], birthdays: [])
        return CountdownEntry(date: .now, snapshot: snapshot, choiceID: nil)
    }
}

#Preview("Days together small", as: .systemSmall) {
    DaysTogetherHomeWidget()
} timeline: {
    LockScreenEntry.sample
    LockScreenEntry.fresh
    LockScreenEntry.empty
}

#Preview("Days together medium", as: .systemMedium) {
    DaysTogetherHomeWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Countdown small", as: .systemSmall) {
    CountdownHomeWidget()
} timeline: {
    CountdownEntry.sample
    CountdownEntry.fresh
    CountdownEntry.empty
}

#Preview("Countdown medium", as: .systemMedium) {
    CountdownHomeWidget()
} timeline: {
    CountdownEntry.sample
    CountdownEntry.oneDate
}

#Preview("Streak", as: .systemSmall) {
    StreakHomeWidget()
} timeline: {
    LockScreenEntry.sample
    LockScreenEntry.fresh
    LockScreenEntry.empty
}

#Preview("Today's question small", as: .systemSmall) {
    DailyQuestionHomeWidget()
} timeline: {
    LockScreenEntry.sample
    LockScreenEntry.empty
}

#Preview("Today's question medium", as: .systemMedium) {
    DailyQuestionHomeWidget()
} timeline: {
    LockScreenEntry.sample
    LockScreenEntry.fresh
}
#endif
