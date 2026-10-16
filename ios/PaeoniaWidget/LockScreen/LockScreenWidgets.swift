#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

// Seven widgets, one kind each, so the person picks only what they want on the
// Lock Screen. They share one cached snapshot (`LockScreenStateService`). The
// drawing widget stays on the Home Screen.

struct DaysTogetherLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.daysTogether,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            DaysTogetherLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenDaysTogetherName))
        .description(String(localized: .widgetLockScreenDaysTogetherDescription))
        .supportedFamilies([.accessoryCircular, .accessoryInline])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct NextCountdownLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.nextCountdown,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            NextCountdownLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenNextCountdownName))
        .description(String(localized: .widgetLockScreenNextCountdownDescription))
        .supportedFamilies([.accessoryRectangular])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct TheirTimeLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.theirTime,
            provider: LockScreenTimelineProvider(schedule: .everyMinute)
        ) { entry in
            TheirTimeLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenTheirTimeName))
        .description(String(localized: .widgetLockScreenTheirTimeDescription))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct DistanceLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.distance,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            DistanceLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenDistanceName))
        .description(String(localized: .widgetLockScreenDistanceDescription))
        .supportedFamilies([.accessoryCircular, .accessoryInline])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct StreakLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.streak,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            StreakLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(LockScreenURL.streak)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenStreakName))
        .description(String(localized: .widgetLockScreenStreakDescription))
        .supportedFamilies([.accessoryCircular])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct DailyQuestionLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.dailyQuestion,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            DailyQuestionLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(LockScreenURL.dailyQuestion)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenQuestionName))
        .description(String(localized: .widgetLockScreenQuestionDescription))
        .supportedFamilies([.accessoryRectangular])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

struct YourMoveLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LockScreenWidgetKind.yourMove,
            provider: LockScreenTimelineProvider(schedule: .daily)
        ) { entry in
            YourMoveLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: .widgetLockScreenYourMoveName))
        .description(String(localized: .widgetLockScreenYourMoveDescription))
        .supportedFamilies([.accessoryCircular])
        .pushHandler(PaeoniaWidgetPushHandler.self)
    }
}

private extension LockScreenEntry {
    static var sample: LockScreenEntry { LockScreenEntry(date: .now, snapshot: .sample(now: .now)) }
    static var empty: LockScreenEntry { LockScreenEntry(date: .now, snapshot: nil) }
}

#Preview("Days together", as: .accessoryCircular) {
    DaysTogetherLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
    LockScreenEntry.empty
}

#Preview("Days together inline", as: .accessoryInline) {
    DaysTogetherLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Next countdown", as: .accessoryRectangular) {
    NextCountdownLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
    LockScreenEntry.empty
}

#Preview("Their time", as: .accessoryCircular) {
    TheirTimeLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Their time rectangular", as: .accessoryRectangular) {
    TheirTimeLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Distance", as: .accessoryCircular) {
    DistanceLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Distance inline", as: .accessoryInline) {
    DistanceLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Streak", as: .accessoryCircular) {
    StreakLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Today's question", as: .accessoryRectangular) {
    DailyQuestionLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}

#Preview("Your move", as: .accessoryCircular) {
    YourMoveLockScreenWidget()
} timeline: {
    LockScreenEntry.sample
}
#endif
