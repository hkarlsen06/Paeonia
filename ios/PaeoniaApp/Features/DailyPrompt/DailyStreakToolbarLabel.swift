import SwiftUI

/// What the streak indicator should show: the live count normally, or a tappable
/// paused look with the broken streak that can still come back, free on its save
/// day and by purchase on the two days after it.
struct StreakPillState: Equatable {
    var count: Int
    var isRestorable: Bool
    var restorableCount: Int
    /// Both partners can still bring the broken streak back for free today.
    var isSavable: Bool
    /// When the free save day ends. The label re-checks at this moment and turns to
    /// the restore offer.
    var saveDeadline: Date?
    /// When the restore offer closes. The label re-checks at this moment so the pill
    /// stops advertising a restore the second it lapses, without waiting for new data.
    var restoreDeadline: Date?
    /// When the live streak ends unless both partners show up first.
    var endsAt: Date?
    /// The live streak ends within `atRiskLeadTime`. Set by `resolved(at:)`.
    private(set) var isAtRisk = false
    private var isAvailable: Bool

    /// How long before the streak ends the pill starts showing the hourglass.
    static let atRiskLeadTime: TimeInterval = 4 * 60 * 60

    static let hidden = StreakPillState(
        count: 0,
        isRestorable: false,
        restorableCount: 0,
        isAvailable: false
    )

    init(
        count: Int,
        isRestorable: Bool,
        restorableCount: Int,
        isSavable: Bool = false,
        saveDeadline: Date? = nil,
        restoreDeadline: Date? = nil,
        endsAt: Date? = nil,
        isAvailable: Bool = true
    ) {
        self.count = count
        self.isRestorable = isRestorable
        self.restorableCount = restorableCount
        self.isSavable = isSavable
        self.saveDeadline = saveDeadline
        self.restoreDeadline = restoreDeadline
        self.endsAt = endsAt
        self.isAvailable = isAvailable
    }

    init(_ streak: CoupleStreak) {
        count = streak.currentCount
        isRestorable = streak.isRestorable
        restorableCount = streak.restorableCount
        isSavable = streak.isSavable
        saveDeadline = streak.saveDeadline
        restoreDeadline = streak.restoreDeadline
        endsAt = streak.endsAt
        isAvailable = true
    }

    /// The pill as it should look at `now`: at the end of the save day the streak can
    /// only be bought back, an offer whose deadline has been reached (or passed) is no
    /// longer restorable and falls back to the live count, and a live streak close to
    /// its end shows the hourglass.
    func resolved(at now: Date) -> StreakPillState {
        var resolved = self
        if isSavable, let saveDeadline, saveDeadline <= now {
            resolved.isSavable = false
            resolved.isRestorable = restorableCount > 0 && (restoreDeadline.map { $0 > now } ?? false)
        }
        if resolved.isRestorable, let restoreDeadline, restoreDeadline <= now {
            resolved.isRestorable = false
        }
        resolved.isAtRisk = resolved.atRiskFrom.map { $0 <= now } ?? false
        return resolved
    }

    /// A broken streak that can still come back, free today or by purchase.
    var isPaused: Bool { isSavable || isRestorable }

    /// When the hourglass appears, or `nil` when there is no live streak to lose.
    /// A paused streak already shows the muted flame, so it never gets the hourglass.
    private var atRiskFrom: Date? {
        guard count >= 1, !isPaused, let endsAt else { return nil }
        return endsAt.addingTimeInterval(-Self.atRiskLeadTime)
    }

    /// The moments the pill looks different without new data.
    var changeDates: [Date] {
        [isSavable ? saveDeadline : nil, restoreDeadline, atRiskFrom].compactMap(\.self).sorted()
    }

    /// The number shown: the broken streak while it can still come back (so it shows
    /// what you'd get back), otherwise the live count.
    var displayCount: Int { isPaused ? restorableCount : count }

    /// A paired surface keeps the streak discoverable even before the first day.
    /// `.hidden` remains available for previews and surfaces without streak data.
    var isVisible: Bool { isAvailable }

    /// Zero is a cooled-down streak, while a paused streak is broken. Both use the
    /// same muted flame treatment.
    var usesMutedFlame: Bool { displayCount == 0 || isPaused }

    /// The live count sits on a milestone, which lasts until the couple's next day
    /// counts. The pill shows a small gold dot, and tapping it replays the moment.
    var isMilestone: Bool { !isPaused && StreakMilestones.isMilestone(count) }
}

/// The couple's streak as a navigation-bar element: the brand flame and the day
/// count, sized to match the brand mark on the bar. Uses the same flame as the
/// completion celebration so the two read as one idea at different sizes. Tapping it
/// opens an informative streak sheet; a slipped streak dims, and opens the restore
/// offer once its free save day is over. The routing lives in the `onTap` handler.
struct DailyStreakToolbarLabel: View {
    let state: StreakPillState
    var onTap: (() -> Void)?

    /// Flame glyph height, matched to the toolbar brand mark (`height: 28`) so the
    /// streak badge reads at the same scale as the logo. Grows with Dynamic Type
    /// like the count next to it.
    @ScaledMetric(relativeTo: .subheadline) private var flameHeight: CGFloat = 22

    var body: some View {
        // Draws again when the save day ends, a restore offer lapses, or the streak gets close to its end,
        // so the pill changes while the screen stays open.
        TimelineView(.explicit(state.changeDates)) { _ in
            tappable(state.resolved(at: .now))
        }
    }

    @ViewBuilder
    private func tappable(_ state: StreakPillState) -> some View {
        // Always tappable when a handler is wired: a healthy streak opens its
        // informative sheet, a broken one its save day or restore offer (decided by
        // the handler). Falls back to a plain label only when no tap is provided.
        if let onTap {
            Button(action: onTap) { label(for: state) }
                .buttonStyle(.plain)
        } else {
            label(for: state)
        }
    }

    private func label(for state: StreakPillState) -> some View {
        // On a milestone day the gold dot belongs to the number, so it sits right
        // against it and the flame moves a little further away.
        // The hourglass hangs off the flame's top right corner, so it needs the same room.
        HStack(spacing: state.isMilestone || state.isAtRisk ? PaeoniaSpacing.space8 : PaeoniaSpacing.space4) {
            FlameShape()
                .fill(flameStyle(for: state))
                .frame(width: flameHeight * 0.84, height: flameHeight)
                .overlay(alignment: .topTrailing) {
                    if state.isAtRisk {
                        Image(systemName: "hourglass")
                            .font(.system(size: flameHeight * 0.5, weight: .bold))
                            .foregroundStyle(.paeoniaTextPrimary)
                            .offset(x: flameHeight * 0.2, y: -flameHeight * 0.1)
                    }
                }

            HStack(spacing: PaeoniaSpacing.space2) {
                if state.isMilestone {
                    Circle()
                        .fill(Color.paeoniaInkGold)
                        .frame(width: 6, height: 6)
                        .shadow(color: .paeoniaInkGold, radius: 3)
                }

                Text(state.displayCount, format: .number)
                    .monospacedDigit()
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        // A slipped streak is dimmed, not crossed out. It is a streak waiting to be
        // lit again, not a failure.
        .foregroundStyle(state.isPaused ? .paeoniaTextSecondary : .paeoniaTextPrimary)
        // Breathing room so the toolbar's glass capsule doesn't crowd the flame and count.
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space4)
        // Make the whole pill a tap target, not just the flame's opaque pixels. The
        // capsule hugs this padded frame, so the shape lines up with the visible glass.
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel(for: state)))
        .accessibilityHint(Text(verbatim: accessibilityHint(for: state)))
    }

    private func accessibilityHint(for state: StreakPillState) -> String {
        if state.isSavable { return String(localized: .streakSaveAction) }
        if state.isRestorable { return String(localized: .streakRestoreBrokenAction) }
        return ""
    }

    private func flameStyle(for state: StreakPillState) -> LinearGradient {
        if state.usesMutedFlame {
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

    /// A slipped streak must not read as a live "N day streak", so it says the streak
    /// is paused and how long it was.
    private func accessibilityLabel(for state: StreakPillState) -> String {
        let streakText = "\(state.displayCount) \(String(localized: .homeStreakLabel))"
        if state.isAtRisk { return String(localized: .streakAtRiskPillAccessibility(streakText)) }
        if state.isMilestone { return String(localized: .streakMilestonePillAccessibility(streakText)) }
        if state.isSavable { return String(localized: .streakSavePillAccessibilityLabel(streakText)) }
        guard state.isRestorable else { return streakText }
        return String(localized: .streakRestorePillAccessibilityLabel(streakText))
    }
}

#if DEBUG
#Preview("Zero") {
    DailyStreakToolbarLabel(
        state: StreakPillState(count: 0, isRestorable: false, restorableCount: 0),
        onTap: {}
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Healthy") {
    DailyStreakToolbarLabel(state: StreakPillState(count: 12, isRestorable: false, restorableCount: 0))
        .padding()
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Milestone day") {
    DailyStreakToolbarLabel(state: StreakPillState(count: 30, isRestorable: false, restorableCount: 0), onTap: {})
        .padding()
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Ends soon") {
    DailyStreakToolbarLabel(
        state: StreakPillState(
            count: 12,
            isRestorable: false,
            restorableCount: 0,
            endsAt: .now.addingTimeInterval(60 * 60)
        ),
        onTap: {}
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Restorable") {
    DailyStreakToolbarLabel(
        state: StreakPillState(
            count: 1,
            isRestorable: true,
            restorableCount: 30,
            restoreDeadline: .now.addingTimeInterval(8)
        ),
        onTap: {}
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
