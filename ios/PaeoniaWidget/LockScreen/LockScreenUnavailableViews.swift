#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

/// The neutral state: signed out, not paired, or nothing saved yet. It shows
/// the widget's own symbol and asks to open Paeonia. It never shows numbers.
struct LockScreenUnavailableView: View {
    @Environment(\.widgetFamily) private var family

    let symbol: String
    let title: LocalizedStringResource

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                // One line for the name, so "Tap to open Paeonia" never gets cut off.
                Label { Text(title) } icon: { Image(systemName: symbol) }
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .widgetAccentable()
                Text(.widgetPlaceholderAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label { Text(.widgetPlaceholderAction) } icon: { Image(systemName: symbol) }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.widgetPlaceholderAction))
        }
    }
}
#endif
