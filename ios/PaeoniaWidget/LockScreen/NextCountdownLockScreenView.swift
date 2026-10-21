#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct NextCountdownLockScreenView: View {
    let entry: LockScreenEntry

    private var countdown: LockScreenCountdown? {
        entry.snapshot.flatMap {
            LockScreenCountdown.next(in: $0.dates, now: entry.date, calendar: .current)
        }
    }

    var body: some View {
        if let countdown {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    // The title is the couple's own text. The system hides it
                    // while the phone is locked and shows it after Face ID.
                    Text(countdown.title)
                        .privacySensitive()
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .widgetAccentable()

                Text(countdown.remaining.text)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Gauge(value: countdown.progress) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .widgetAccentable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LockScreenUnavailableView(symbol: "calendar", title: .widgetLockScreenNextCountdownName)
        }
    }
}
#endif
