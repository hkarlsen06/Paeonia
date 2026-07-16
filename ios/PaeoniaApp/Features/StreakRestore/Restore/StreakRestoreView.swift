import Foundation
import SwiftUI

/// The streak-restore offer: a calm, paywall-styled surface that shows the lost
/// streak as a dim "broken" flame and lets either partner buy it back. On success
/// it turns into a celebratory streak detail screen with the restored count.
struct StreakRestoreView: View {
    @State private var viewModel: StreakRestoreViewModel
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
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
        .onChange(of: viewModel.error) { _, error in
            showBanner(for: error)
        }
    }

    private var restoreOffer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            restoreOfferContent(now: context.date)
        }
    }

    private func restoreOfferContent(now: Date) -> some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            deadlineCountdown(now: now)

            Spacer()

            PaeoniaStreakFlame(
                count: viewModel.restorableCount,
                playsCelebration: false,
                isBroken: true
            )

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(.streakRestoreTitle)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(.streakRestoreMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            Spacer()

            actions(now: now)
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

    @ViewBuilder
    private func deadlineCountdown(now: Date) -> some View {
        if let text = StreakRestoreCountdownText.format(deadline: restoreDeadline, now: now) {
            Text(verbatim: text)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                .accessibilityLabel(Text(verbatim: text))
        }
    }

    private func actions(now: Date) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: restore) {
                if viewModel.isPurchasing {
                    ProgressView().tint(.paeoniaTextInverse)
                } else {
                    Text(verbatim: buyTitle)
                }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(
                viewModel.isPurchasing
                    || StreakRestoreDeadlineState.resolve(deadline: restoreDeadline, now: now).blocksPurchase
            )
            // The spinner fades in over the price label instead of snapping while
            // the App Store purchase settles.
            .animation(PaeoniaMotion.stateChange, value: viewModel.isPurchasing)

            Button(action: onClose) {
                Text(.streakRestoreNotNow)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            .disabled(viewModel.isPurchasing)

            PaeoniaLegalLinksView()
        }
    }

    private var buyTitle: String {
        let base = String(localized: .streakRestoreBuyButton)
        guard let price = viewModel.priceText else { return base }
        return "\(base) · \(price)"
    }

    private func restore() {
        Task { _ = await viewModel.purchase() }
    }

    private func showBanner(for error: StreakRestoreError?) {
        guard let error else { return }
        bannerCenter.show(.error(message: error.message))
        viewModel.clearError()
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
        self == .expired
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
#Preview {
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
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
