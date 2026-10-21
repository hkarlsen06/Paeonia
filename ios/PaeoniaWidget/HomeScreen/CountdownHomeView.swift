#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

/// The Home Screen countdown: one countdown or birthday. The medium size lists
/// the dates that come after it.
struct CountdownHomeView: View {
    @Environment(\.widgetFamily) private var family

    let entry: CountdownEntry

    private var items: [LockScreenDateItem] {
        guard let snapshot = entry.snapshot else { return [] }
        return LockScreenDates.items(
            in: snapshot.dates,
            today: LockScreenCalendarDate(containing: entry.date, in: .current)
        )
    }

    private var partnerName: String {
        entry.snapshot?.partnerFirstName ?? ""
    }

    var body: some View {
        if entry.snapshot == nil {
            HomeWidgetUnavailableView(
                symbol: "calendar",
                title: .widgetHomeCountdownName,
                message: .widgetPlaceholderAction
            )
        } else if let shown = LockScreenDates.selected(id: entry.choiceID, in: items) {
            content(shown)
                .accessibilityElement(children: .combine)
                .widgetURL(LockScreenURL.dates)
        } else {
            HomeWidgetUnavailableView(
                symbol: "calendar.badge.plus",
                title: .widgetHomeCountdownName,
                message: .widgetHomeCountdownAddDate
            )
            .widgetURL(LockScreenURL.dates)
        }
    }

    @ViewBuilder
    private func content(_ shown: LockScreenDateItem) -> some View {
        if family == .systemSmall {
            hero(shown)
        } else {
            HStack(alignment: .top, spacing: 14) {
                hero(shown)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(Color.paeoniaWidgetTextPrimary.opacity(0.14))
                    .frame(width: 1)
                    .accessibilityHidden(true)
                comingUp(after: shown)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func hero(_ shown: LockScreenDateItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title(shown)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(2)
            dateLine(shown)
            Spacer(minLength: 0)
            switch shown.remaining {
            case .today, .tomorrow:
                HomeWidgetHeroText(text: shown.remaining.text)
            case let .days(days):
                HomeWidgetHeroText(text: days.formatted())
                Text(.widgetHomeCountdownUnit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.paeoniaWidgetTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The date with its symbol, such as "Sat 3 Oct".
    private func dateLine(_ item: LockScreenDateItem) -> some View {
        Label {
            Text(dateText(item))
        } icon: {
            Image(systemName: item.symbol)
                .foregroundStyle(.paeoniaWidgetAccentPrimary)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.paeoniaWidgetTextSecondary)
        .lineLimit(1)
        .widgetAccentable()
    }

    private func comingUp(after shown: LockScreenDateItem) -> some View {
        let next = LockScreenDates.comingUp(after: shown, in: items, limit: 2)
        return VStack(alignment: .leading, spacing: 8) {
            if next.isEmpty {
                Spacer(minLength: 0)
                Label { Text(.widgetHomeCountdownAddMore) } icon: { Image(systemName: "plus.circle.fill") }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.paeoniaWidgetTextSecondary)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
            } else {
                Text(.widgetHomeCountdownComingUp)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaWidgetAccentPrimary)
                    .widgetAccentable()
                ForEach(next) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: LockScreenDateItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                title(item)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.paeoniaWidgetTextPrimary)
                    .lineLimit(1)
                Text(dateText(item))
                    .font(.caption2)
                    .foregroundStyle(.paeoniaWidgetTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(item.remaining.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The couple's own text is hidden on a locked phone, like on the Lock Screen widget.
    @ViewBuilder
    private func title(_ item: LockScreenDateItem) -> some View {
        if item.isPrivateTitle {
            Text(item.title(partnerName: partnerName)).privacySensitive()
        } else {
            Text(item.title(partnerName: partnerName))
        }
    }

    private func dateText(_ item: LockScreenDateItem) -> String {
        guard let date = item.date.startOfDay(in: .current) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
#endif
