#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

// Shared pieces of the Home Screen widgets that read the snapshot. They sit on
// the same plum background as the drawing widget (`PaeoniaWidgetTheme.swift`).

/// The small line at the top of a widget: a symbol and the widget's name.
struct HomeWidgetHeader: View {
    let symbol: String
    let title: Text

    var body: some View {
        Label { title } icon: { Image(systemName: symbol) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.paeoniaWidgetAccentPrimary)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// A big number or word. It shrinks before it gets cut off.
struct HomeWidgetHeroText: View {
    @Environment(\.widgetFamily) private var family

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: family == .systemSmall ? 44 : 52, weight: .bold, design: .rounded))
            .foregroundStyle(.paeoniaWidgetTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A thin bar from 0 to 1, such as how far along the next milestone is.
struct HomeWidgetProgressBar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(Color.paeoniaWidgetTextPrimary.opacity(0.16))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.paeoniaWidgetAccentPrimary)
                        .frame(width: proxy.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 6)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

/// A button-shaped line that tells the person what a tap does. The whole widget
/// is the tap target, so this is not a control of its own.
struct HomeWidgetActionPill: View {
    let title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.paeoniaWidgetBackground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.paeoniaWidgetAccentPrimary, in: Capsule())
            .widgetAccentable()
    }
}

/// The state with nothing to show yet: signed out, not paired, or the person has
/// not added the date yet. It names the widget and says what to do. It never
/// shows numbers or text from the couple.
struct HomeWidgetUnavailableView: View {
    @Environment(\.widgetFamily) private var family

    let symbol: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeWidgetHeader(symbol: symbol, title: Text(title))
            Spacer(minLength: 0)
            Text(message)
                .font(family == .systemSmall ? .callout.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.system(size: family == .systemSmall ? 34 : 44, weight: .semibold))
                .foregroundStyle(Color.paeoniaWidgetAccentPrimary.opacity(0.3))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
