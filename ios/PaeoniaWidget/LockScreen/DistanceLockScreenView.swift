#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct DistanceLockScreenView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LockScreenEntry

    private var distance: LockScreenDistance {
        LockScreenDistance(entry.snapshot?.distance)
    }

    var body: some View {
        if entry.snapshot == nil {
            LockScreenUnavailableView(symbol: "mappin.and.ellipse", title: .widgetLockScreenDistanceName)
        } else if family == .accessoryInline {
            inline
        } else {
            circular
        }
    }

    @ViewBuilder
    private var inline: some View {
        switch distance {
        case .unavailable:
            Label { Text(.widgetLockScreenDistanceTurnOn) } icon: { Image(systemName: "mappin.and.ellipse") }
        case .together:
            Label { Text(.widgetLockScreenDistanceTogether) } icon: { Image(systemName: "heart.fill") }
        case let .apart(meters):
            Label {
                Text(.widgetLockScreenDistanceApart(LockScreenDistance.text(meters: meters, locale: .current).combined))
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                switch distance {
                case .unavailable:
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 12)).accessibilityHidden(true)
                    Text(verbatim: "–").font(.system(size: 17, weight: .bold, design: .rounded))
                case .together:
                    Image(systemName: "heart.fill").font(.system(size: 14)).accessibilityHidden(true)
                    Text(.widgetLockScreenDistanceTogether)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                case let .apart(meters):
                    let text = LockScreenDistance.text(meters: meters, locale: .current)
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11)).accessibilityHidden(true)
                    Text(text.number)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(text.unit).font(.system(size: 9, weight: .medium, design: .rounded))
                }
            }
            .padding(.horizontal, 4)
            .widgetAccentable()
        }
    }
}
#endif
