#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct StreakLockScreenView: View {
    let entry: LockScreenEntry

    private var streak: LockScreenStreak? {
        entry.snapshot.flatMap { LockScreenStreak($0, at: entry.date) }
    }

    var body: some View {
        if let streak {
            ZStack {
                AccessoryWidgetBackground()
                // Dim track under the lit halves. The two halves are one closed
                // circle when both partners are active.
                StreakRingView(
                    ring: streak.ring,
                    lineWidth: Self.ringWidth,
                    track: AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.2)),
                    lit: AnyShapeStyle(HierarchicalShapeStyle.primary)
                )
                .padding(Self.ringInset)
                VStack(spacing: -1) {
                    Image(systemName: "flame.fill").font(.system(size: 11))
                    Text(streak.count.formatted())
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
            }
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.widgetLockScreenStreakAccessibility(streak.count)))
        } else {
            LockScreenUnavailableView(symbol: "flame", title: .widgetLockScreenStreakName)
        }
    }

    private static let ringWidth: CGFloat = 3
    private static let ringInset: CGFloat = 3
}
#endif
