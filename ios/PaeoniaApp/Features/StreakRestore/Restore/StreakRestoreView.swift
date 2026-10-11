import Foundation
import SwiftUI

/// The streak-restore offer: a calm, paywall-styled surface that shows the lost
/// streak as a dim "broken" flame and lets either partner buy it back. On success
/// it turns into a celebratory streak detail screen with the restored count.
struct StreakRestoreView: View {
    @State private var viewModel: StreakRestoreViewModel
    var onClose: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var restoreDeadline: Date? {
        viewModel.streak.restoreDeadline
    }

    init(viewModel: StreakRestoreViewModel, onClose: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            if let restoredCount = viewModel.restoredCount {
                restoredContent(count: restoredCount)
                    .transition(.opacity)
            } else {
                restoreOffer
                    .transition(.opacity)
            }
        }
        // The purchase settles concurrently, so the broken-flame offer dissolves
        // into the restored celebration instead of swapping the instant the
        // transaction lands. A fade only, so Reduce Motion needs no branch.
        .animation(PaeoniaMotion.meaningfulMoment, value: viewModel.restoredCount == nil)
        .task { await viewModel.load() }
        // The shared top banner sits under this sheet, so errors show inline (see
        // `errorCaption`). VoiceOver does not see new text on its own, so say it.
        .onChange(of: viewModel.error) { _, error in
            guard let error else { return }
            AccessibilityNotification.Announcement(error.message).post()
        }
    }

    private var restoreOffer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            restoreOfferContent(now: context.date)
        }
    }

    private func restoreOfferContent(now: Date) -> some View {
        // Once the deadline passes there is nothing left to buy, so the countdown and
        // the buy button give way to a calm note. The flame stays in the same place in
        // the stack so it does not replay its drain.
        let hasEnded = StreakRestoreDeadlineState.resolve(deadline: restoreDeadline, now: now).blocksPurchase

        return VStack(spacing: PaeoniaSpacing.space24) {
            if !hasEnded {
                deadlineCountdown(now: now)
            }

            Spacer()

            PaeoniaStreakFlame(
                count: viewModel.restorableCount,
                playsCelebration: false,
                isBroken: true
            )

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(title(hasEnded: hasEnded))
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(message(hasEnded: hasEnded))
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            Spacer()

            actions(hasEnded: hasEnded)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaSurfacePrimary)
    }

    private func restoredContent(count: Int) -> some View {
        StreakDetailView(
            streak: restoredStreak(count: count),
            title: .streakRestoreSuccessTitle,
            message: .streakRestoreSuccessMessage,
            playsCelebration: true,
            ambientMotion: false,
            onClose: onClose
        )
    }

    private func restoredStreak(count: Int) -> CoupleStreak {
        CoupleStreak(
            currentCount: count,
            longestCount: max(viewModel.streak.longestCount, count),
            lastQualifiedDate: viewModel.streak.lastQualifiedDate,
            restoreAvailable: false,
            restorableCount: 0,
            restoreDeadline: nil
        )
    }

    private func title(hasEnded: Bool) -> LocalizedStringResource {
        hasEnded ? .streakRestoreExpiredTitle : .streakRestoreTitle
    }

    private func message(hasEnded: Bool) -> LocalizedStringResource {
        hasEnded ? .streakRestoreExpiredMessage : .streakRestoreMessage
    }

    @ViewBuilder
    private func deadlineCountdown(now: Date) -> some View {
        if let deadline = restoreDeadline,
           let text = StreakRestoreCountdownText.format(deadline: deadline, now: now) {
            Text(verbatim: text)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                .accessibilityLabel(Text(verbatim: spokenTimeLeft(until: deadline, now: now)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// "23 hours, 41 minutes left", rounded up to the minute so VoiceOver does not
    /// read a changing number of seconds.
    private func spokenTimeLeft(until deadline: Date, now: Date) -> String {
        let minutesLeft = Int(ceil(max(0, deadline.timeIntervalSince(now)) / 60))
        let duration = Duration.seconds(minutesLeft * 60)
        let text = duration.formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return String(localized: .streakRestoreCountdownAccessibilityLabel(text))
    }

    private func actions(hasEnded: Bool) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            errorCaption

            if hasEnded {
                Button(action: onClose) {
                    Text(.commonDone)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
                .disabled(viewModel.isPurchasing)
            } else {
                buyButton

                Button(action: onClose) {
                    Text(.streakRestoreNotNow)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                .disabled(viewModel.isPurchasing)

                PaeoniaLegalLinksView()
            }
        }
    }

    /// The reason the last attempt failed, right above the buttons. It stays until
    /// the next attempt so it is still there when the person looks back at the screen.
    @ViewBuilder
    private var errorCaption: some View {
        if let error = viewModel.error {
            Text(verbatim: error.message)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buyButton: some View {
        Button(action: buy) {
            if viewModel.isPurchasing || viewModel.isLoading {
                ProgressView().tint(.paeoniaTextInverse)
            } else if viewModel.isAwaitingConfirmation {
                Text(.streakRestoreCheckAgainButton)
            } else if viewModel.needsPriceRetry {
                Text(.paywallProductsRetry)
            } else {
                Text(verbatim: buyTitle)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        // Not buyable until the price has loaded, and never again once the streak
        // is back, the time is up, or a payment already went through.
        .disabled(
            viewModel.isPurchasing
                || viewModel.isLoading
                || !viewModel.hasFinishedLoadingProducts
                || viewModel.blockingError != nil
        )
        // The spinner fades in over the price label instead of snapping while
        // the App Store purchase settles.
        .animation(PaeoniaMotion.stateChange, value: viewModel.isPurchasing)
    }

    private var buyTitle: String {
        let base = String(localized: .streakRestoreBuyButton)
        guard let price = viewModel.priceText else { return base }
        return "\(base) · \(price)"
    }

    private func buy() {
        Task {
            if viewModel.needsPriceRetry {
                await viewModel.load()
            } else {
                _ = await viewModel.purchase()
            }
        }
    }
}

nonisolated enum StreakRestoreDeadlineState: Equatable {
    case unavailable
    case active
    case expired

    static func resolve(deadline: Date?, now: Date) -> StreakRestoreDeadlineState {
        guard let deadline else { return .unavailable }
        return deadline > now ? .active : .expired
    }

    var blocksPurchase: Bool {
        self != .active
    }
}

nonisolated enum StreakRestoreCountdownText {
    static func format(deadline: Date?, now: Date) -> String? {
        guard let deadline else { return nil }

        let secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        let hours = secondsRemaining / 3_600
        let minutes = (secondsRemaining % 3_600) / 60
        let seconds = secondsRemaining % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#if DEBUG
#Preview("Offer") {
    StreakRestoreView(
        viewModel: StreakRestoreViewModel(
            streak: CoupleStreak(
                currentCount: 1,
                longestCount: 30,
                lastQualifiedDate: "2026-06-26",
                restoreAvailable: true,
                restorableCount: 30,
                restoreDeadline: .now.addingTimeInterval(86_400)
            ),
            userID: nil
        )
    )
    .preferredColorScheme(.dark)
}

#Preview("Time is up") {
    StreakRestoreView(
        viewModel: StreakRestoreViewModel(
            streak: CoupleStreak(
                currentCount: 0,
                longestCount: 30,
                lastQualifiedDate: "2026-06-26",
                restoreAvailable: true,
                restorableCount: 30,
                restoreDeadline: .now.addingTimeInterval(-60)
            ),
            userID: nil
        )
    )
    .preferredColorScheme(.dark)
}
#endif
