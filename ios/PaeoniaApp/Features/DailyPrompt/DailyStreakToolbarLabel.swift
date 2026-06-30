import SwiftUI

/// What the streak indicator should show: the live count normally, or a tappable
/// "broken" look advertising the lost streak you can buy back.
struct StreakPillState: Equatable {
    var count: Int
    var isRestorable: Bool
    var restorableCount: Int

    static let hidden = StreakPillState(count: 0, isRestorable: false, restorableCount: 0)

    init(count: Int, isRestorable: Bool, restorableCount: Int) {
        self.count = count
        self.isRestorable = isRestorable
        self.restorableCount = restorableCount
    }

    init(_ streak: CoupleStreak) {
        count = streak.currentCount
        isRestorable = streak.isRestorable
        restorableCount = streak.restorableCount
    }

    /// The number shown: the lost streak while a restore is offered (so it advertises
    /// what you'd get back), otherwise the live count.
    var displayCount: Int { isRestorable ? restorableCount : count }

    /// Show it only when there's a streak to celebrate or a restore to offer.
    var isVisible: Bool { displayCount >= 1 }
}

/// The couple's streak as a navigation-bar element: the brand flame and the day
/// count, sized to match the brand mark on the bar. Uses the same flame as the
/// completion celebration so the two read as one idea at different sizes. Tapping it
/// opens an informative streak sheet; a slipped streak dims and opens the restore
/// offer instead. The healthy-vs-broken routing lives in the `onTap` handler.
struct DailyStreakToolbarLabel: View {
    let state: StreakPillState
    var onTap: (() -> Void)?

    /// Flame glyph height, matched to the toolbar brand mark (`height: 28`) so the
    /// streak badge reads at the same scale as the logo.
    private let flameHeight: CGFloat = 22

    var body: some View {
        // Always tappable when a handler is wired: a healthy streak opens its
        // informative sheet, a broken one opens the restore offer (decided by the
        // handler). Falls back to a plain label only when no tap is provided.
        if let onTap {
            Button(action: onTap) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            FlameShape()
                .fill(flameStyle)
                .frame(width: flameHeight * 0.84, height: flameHeight)

            Text(state.displayCount, format: .number)
                .monospacedDigit()
                // A slipped streak reads as cancelled — its count is the lost streak
                // you'd buy back, so cross it out (no draw-on here, unlike the sheet).
                .strikethrough(state.isRestorable, color: .paeoniaTextSecondary)
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .foregroundStyle(state.isRestorable ? .paeoniaTextSecondary : .paeoniaTextPrimary)
        // Breathing room so the toolbar's glass capsule doesn't crowd the flame and count.
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space4)
        // Make the whole pill a tap target, not just the flame's opaque pixels — the
        // capsule hugs this padded frame, so the shape lines up with the visible glass.
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var flameStyle: LinearGradient {
        if state.isRestorable {
            return LinearGradient(
                colors: [.paeoniaTextSecondary.opacity(0.6), .paeoniaSurfacePressed],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [.paeoniaAccentPrimary, .paeoniaInkGold],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var accessibilityLabel: String {
        let base = "\(state.displayCount) \(String(localized: .homeStreakLabel))"
        guard state.isRestorable else { return base }
        return "\(base), \(String(localized: .streakRestoreBrokenAction))"
    }
}

#if DEBUG
#Preview("Healthy") {
    DailyStreakToolbarLabel(state: StreakPillState(count: 12, isRestorable: false, restorableCount: 0))
        .padding()
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Restorable") {
    DailyStreakToolbarLabel(
        state: StreakPillState(count: 1, isRestorable: true, restorableCount: 30),
        onTap: {}
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
