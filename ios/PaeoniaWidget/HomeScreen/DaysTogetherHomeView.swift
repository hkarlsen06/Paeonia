#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

/// Days together on the Home Screen: the count, and how far it is to the next
/// milestone. The medium size adds the day the couple got together.
struct DaysTogetherHomeView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LockScreenEntry

    private var model: LockScreenDaysTogether? {
        LockScreenDaysTogether(startedOn: entry.snapshot?.startedOn, now: entry.date, calendar: .current)
    }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                HomeWidgetUnavailableView(
                    symbol: "heart.fill",
                    title: .widgetLockScreenDaysTogetherName,
                    message: .widgetPlaceholderAction
                )
            } else if let model {
                content(model)
                    .accessibilityElement(children: .combine)
                    .widgetURL(LockScreenURL.dates)
            } else {
                HomeWidgetUnavailableView(
                    symbol: "heart.fill",
                    title: .widgetLockScreenDaysTogetherName,
                    message: .widgetHomeDaysTogetherSetDate
                )
                .widgetURL(LockScreenURL.dates)
            }
        }
    }

    @ViewBuilder
    private func content(_ model: LockScreenDaysTogether) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                HomeWidgetHeader(symbol: "heart.fill", title: Text(.widgetLockScreenDaysTogetherName))
                Spacer(minLength: 0)
                HomeWidgetHeroText(text: model.days.formatted())
                Spacer(minLength: 6)
                milestone(model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HomeWidgetHeader(symbol: "heart.fill", title: Text(.widgetLockScreenDaysTogetherName))
                    Spacer(minLength: 0)
                    HomeWidgetHeroText(text: model.days.formatted())
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer(minLength: 0)
                    if let startedOn = entry.snapshot?.startedOn, let start = startedOn.startOfDay(in: .current) {
                        Text(.widgetHomeDaysTogetherSince)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.paeoniaWidgetTextSecondary)
                        Text(start.formatted(.dateTime.day().month(.wide).year()))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.paeoniaWidgetTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 6)
                    milestone(model)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func milestone(_ model: LockScreenDaysTogether) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HomeWidgetProgressBar(value: model.progress)
            Text(.widgetHomeDaysTogetherNextMilestone(model.nextMilestone))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.paeoniaWidgetTextSecondary)
                .lineLimit(1)
        }
    }
}
#endif
