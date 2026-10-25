#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct DaysTogetherLockScreenView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LockScreenEntry

    private var model: LockScreenDaysTogether? {
        LockScreenDaysTogether(startedOn: entry.snapshot?.startedOn, now: entry.date, calendar: .current)
    }

    var body: some View {
        if let model {
            if family == .accessoryInline {
                Label { Text(.widgetLockScreenDaysTogetherInline(model.days)) } icon: {
                    Image(systemName: "heart.fill")
                }
            } else {
                ring(model)
            }
        } else {
            LockScreenUnavailableView(symbol: "heart", title: .widgetLockScreenDaysTogetherName)
        }
    }

    private func ring(_ model: LockScreenDaysTogether) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: model.progress) {
                Text(.widgetLockScreenDaysTogetherName)
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Text(model.days.formatted())
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(.widgetLockScreenDaysTogetherUnit(count: model.days))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        }
    }
}
#endif
