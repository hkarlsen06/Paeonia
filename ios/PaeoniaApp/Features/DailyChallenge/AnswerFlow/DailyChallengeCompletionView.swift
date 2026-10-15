import SwiftUI

/// The streak screen the answer flow turns over to once the user's questions
/// are answered. A slipped streak's version offers to buy the streak back in place.
struct DailyChallengeCompletionView: View {
    let streak: Int
    /// The partner's display name, so the finish copy and CTA name them.
    let partnerName: String
    /// The lost streak length when a restore is on offer; `nil` for a normal,
    /// celebratory finish. When set (and not yet restored), the flame reads
    /// "slipped" and a buy-it-back action is offered above Done.
    var restorableCount: Int?
    /// The in-place buy action follows the same server-owned restore window as
    /// the standalone offer. Keeping it here prevents a completion screen left
    /// open in the foreground from selling an already-expired restore.
    var restoreDeadline: Date?
    /// Drives the in-place restore purchase. Present only for a slipped streak's
    /// completion; `nil` for a normal finish. Once its `restoredCount` lands the
    /// screen turns celebratory and the flame reignites and refills.
    var restoreViewModel: StreakRestoreViewModel?
    var hasPartnerQuestionsToAnswer = false
    var onOpenPartnerQuestions: () -> Void = {}
    /// The streak milestone this finish reaches, when this phone has not celebrated
    /// it yet. The screen then shows the milestone moment instead of the usual copy.
    var milestone: Int?
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Holds the supporting copy and actions back for a beat so the flame lands
    /// first, then lifts them in. The flame itself is always present so its count-up
    /// starts the instant the screen arrives.
    @State private var showDetails = false

    /// The restored streak length once a purchase (or a recovered pending one) lands.
    private var restoredCount: Int? { restoreViewModel?.restoredCount }
    private var isRestored: Bool { restoredCount != nil }
    private var isPurchasing: Bool { restoreViewModel?.isPurchasing ?? false }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            completionContent(now: context.date)
        }
        // Reignite-and-refill the flame (and swap the copy) once a restore lands.
        .animation(reduceMotion ? nil : PaeoniaMotion.celebrationReveal, value: restoredCount)
        .onAppear(perform: revealDetails)
        .task {
            // Load the price and re-apply any paid-but-unconfirmed restore, but only
            // for a slipped streak's completion. A normal finish has no purchase.
            guard restorableCount != nil else { return }
            await restoreViewModel?.load()
        }
        // The shared top banner sits under this full-screen cover, so restore errors
        // show inline above the buttons. VoiceOver does not see new text on its own.
        .onChange(of: restoreViewModel?.error) { _, error in
            guard let error else { return }
            AccessibilityNotification.Announcement(error.message).post()
        }
    }

    private func completionContent(now: Date) -> some View {
        VStack(spacing: PaeoniaSpacing.space32) {
            Spacer()

            flame(now: now)
                .transition(.opacity)

            VStack(spacing: PaeoniaSpacing.space8) {
                if showsMilestone(now: now) {
                    Text(.streakMilestoneEyebrow)
                        .font(PaeoniaTypography.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(Color.paeoniaInkGold)
                }

                Text(titleText(now: now))
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(messageText(now: now))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .modifier(StreakDetailReveal(shown: showDetails))

            Spacer()

            actions(now: now)
                .modifier(StreakDetailReveal(shown: showDetails))
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The hero flame: slipped and cold before a restore, then a fresh warm flame
    /// that fills from empty and counts up once the streak is bought back, the
    /// "coming back to life" moment. Distinct ids so the restored flame is a new
    /// view and replays its fill-up celebration.
    @ViewBuilder
    private func flame(now: Date) -> some View {
        if let restoredCount {
            PaeoniaStreakFlame(count: restoredCount, playsCelebration: true)
                .id("streak-restored")
        } else if let restorableCount, isRestorable(now: now) {
            PaeoniaStreakFlame(count: restorableCount, isBroken: true)
                .id("streak-broken")
        } else {
            PaeoniaStreakFlame(count: streak, playsCelebration: true)
                .id("streak-earned")
        }
    }

    /// A restore, or a restore still on offer, has its own copy, so the milestone
    /// moment shows only on an ordinary finish.
    private func showsMilestone(now: Date) -> Bool {
        milestone != nil && !isRestored && !isRestorable(now: now)
    }

    private func titleText(now: Date) -> LocalizedStringResource {
        if isRestored { return .streakRestoreSuccessTitle }
        if let milestone, showsMilestone(now: now) { return StreakMilestoneCopy.title(days: milestone) }
        return .dailyChallengeFlowAllDoneTitle
    }

    private func messageText(now: Date) -> LocalizedStringResource {
        if isRestored { return .streakRestoreSuccessMessage }
        if isRestorable(now: now) { return .streakRestoreMessage }
        if let milestone, showsMilestone(now: now) { return StreakMilestoneCopy.message(days: milestone) }
        return .dailyChallengeFlowAllDoneMessage(partnerName)
    }

    private func isRestorable(now: Date) -> Bool {
        guard restorableCount != nil, !isRestored else { return false }
        return StreakRestoreDeadlineState.resolve(
            deadline: restoreDeadline,
            now: now
        ) == .active
    }

    /// Lifts the copy and actions in shortly after the flame appears. Under Reduce
    /// Motion they are simply shown, with no delay or movement.
    private func revealDetails() {
        guard !showDetails else { return }
        if reduceMotion {
            showDetails = true
        } else {
            withAnimation(PaeoniaMotion.meaningfulMoment.delay(0.28)) {
                showDetails = true
            }
        }
    }

    @ViewBuilder
    private func actions(now: Date) -> some View {
        if isRestorable(now: now) {
            restorableActions(now: now)
        } else {
            finishedActions
        }
    }

    /// The buy-it-back action for a slipped streak: a real purchase button (showing
    /// the price once it loads) that calls StoreKit directly, rather than opening a
    /// second, near-identical restore screen.
    private func restorableActions(now: Date) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if let error = restoreViewModel?.error {
                Text(verbatim: error.message)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            purchaseButton(now: now)

            partnerQuestionsButton(style: .secondary)

            Button(action: onDone) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
        }
    }

    private func purchaseButton(now: Date) -> some View {
        Button(action: purchase) {
            if isPurchasing || restoreViewModel?.isLoading == true {
                ProgressView().tint(.paeoniaTextInverse)
            } else if restoreViewModel?.isAwaitingConfirmation == true {
                Text(.streakRestoreCheckAgainButton)
            } else if restoreViewModel?.needsPriceRetry == true {
                Text(.paywallProductsRetry)
            } else {
                Text(verbatim: buyTitle)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        // Same rules as the restore sheet: not buyable until the price has loaded,
        // and never again once a payment went through or the time is up.
        .disabled(
            isPurchasing
                || restoreViewModel?.isLoading == true
                || restoreViewModel?.hasFinishedLoadingProducts != true
                || restoreViewModel?.blockingError != nil
                || StreakRestoreDeadlineState.resolve(
                    deadline: restoreDeadline,
                    now: now
                ).blocksPurchase
        )
    }

    /// Actions for a normal celebratory finish and, after a restore, the revived
    /// streak too: pick up optional partner questions, or just finish.
    @ViewBuilder
    private var finishedActions: some View {
        if hasPartnerQuestionsToAnswer {
            VStack(spacing: PaeoniaSpacing.space12) {
                partnerQuestionsButton(style: .primary)

                Button(action: onDone) {
                    Text(.dailyChallengeFlowDoneButton)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            }
        } else {
            Button(action: onDone) {
                Text(.dailyChallengeFlowDoneButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        }
    }

    /// The buy button's title: "Restore streak", with the price appended once the
    /// consumable has loaded.
    private var buyTitle: String {
        let base = String(localized: .streakRestoreBuyButton)
        guard let price = restoreViewModel?.priceText else { return base }
        return "\(base) · \(price)"
    }

    private func purchase() {
        guard let restoreViewModel else { return }
        Task {
            if restoreViewModel.needsPriceRetry {
                await restoreViewModel.load()
            } else {
                _ = await restoreViewModel.purchase()
            }
        }
    }

    @ViewBuilder
    private func partnerQuestionsButton(style: PartnerQuestionsButtonStyle) -> some View {
        if hasPartnerQuestionsToAnswer {
            switch style {
            case .primary:
                Button(action: onOpenPartnerQuestions) {
                    Text(.dailyChallengeFlowPartnerQuestionsButton(partnerName))
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
            case .secondary:
                Button(action: onOpenPartnerQuestions) {
                    Text(.dailyChallengeFlowPartnerQuestionsButton(partnerName))
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        }
    }

    private enum PartnerQuestionsButtonStyle {
        case primary
        case secondary
    }
}

/// Fades and lifts the streak screen's supporting copy and actions in after the
/// flame has landed. Toggling `shown` (animated by the caller) plays the entrance;
/// the small offset gives the content a gentle rise rather than a flat fade.
private struct StreakDetailReveal: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : PaeoniaSpacing.space12)
    }
}

#if DEBUG
#Preview("Completion") {
    DailyChallengeCompletionView(streak: 7, partnerName: "Oda", restorableCount: nil, onDone: {})
        .background(.paeoniaBackgroundPrimary)
        .environment(PaeoniaBannerCenter())
        .preferredColorScheme(.dark)
}

#Preview("Completion · milestone") {
    DailyChallengeCompletionView(streak: 7, partnerName: "Oda", restorableCount: nil, milestone: 7, onDone: {})
        .background(.paeoniaBackgroundPrimary)
        .environment(PaeoniaBannerCenter())
        .preferredColorScheme(.dark)
}

#Preview("Completion · streak slipped") {
    DailyChallengeCompletionView(
        streak: 1,
        partnerName: "Oda",
        restorableCount: 30,
        restoreViewModel: StreakRestoreViewModel(
            streak: CoupleStreak(
                currentCount: 1,
                longestCount: 30,
                lastQualifiedDate: "2026-06-26",
                restoreAvailable: true,
                restorableCount: 30,
                restoreDeadline: .now.addingTimeInterval(86_400)
            ),
            userID: nil
        ),
        onDone: {}
    )
    .background(.paeoniaBackgroundPrimary)
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
