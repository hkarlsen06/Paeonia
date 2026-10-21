#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

/// The streak on the Home Screen: the same ring as the Lock Screen widget, bigger.
/// The left half is for this person and the right half for the partner.
struct StreakHomeView: View {
    let entry: LockScreenEntry

    private var streak: LockScreenStreak? {
        entry.snapshot.flatMap { LockScreenStreak($0, at: entry.date) }
    }

    var body: some View {
        if let streak {
            content(streak)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(.widgetLockScreenStreakAccessibility(streak.count)))
                .accessibilityValue(Text(caption(streak)))
                .widgetURL(LockScreenURL.streak)
        } else {
            HomeWidgetUnavailableView(
                symbol: "flame.fill",
                title: .widgetLockScreenStreakName,
                message: .widgetPlaceholderAction
            )
        }
    }

    private func content(_ streak: LockScreenStreak) -> some View {
        VStack(spacing: 6) {
            ZStack {
                StreakRingView(
                    ring: streak.ring,
                    lineWidth: 8,
                    track: AnyShapeStyle(Color.paeoniaWidgetTextPrimary.opacity(0.16)),
                    lit: AnyShapeStyle(Color.paeoniaWidgetAccentPrimary)
                )
                .widgetAccentable()
                VStack(spacing: -2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                        .foregroundStyle(.paeoniaWidgetAccentPrimary)
                        .widgetAccentable()
                    Text(streak.count.formatted())
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.paeoniaWidgetTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 14)
            }
            .padding(4)
            Text(caption(streak))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.paeoniaWidgetTextSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
    }

    /// Says who still has to take part today.
    private func caption(_ streak: LockScreenStreak) -> String {
        let partner = entry.snapshot?.partnerFirstName ?? ""
        return switch streak.ring {
        case .both: String(localized: .widgetHomeStreakBoth)
        case .me: String(localized: .widgetHomeStreakWaitingForPartner(partner))
        case .partner: String(localized: .widgetHomeStreakYourTurn(partner))
        case .neither: String(localized: streak.count < 1 ? .widgetHomeStreakStart : .widgetHomeStreakNeither)
        }
    }
}
#endif
