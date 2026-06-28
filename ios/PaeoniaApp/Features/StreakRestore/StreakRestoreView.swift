import SwiftUI

/// The streak-restore offer: a calm, paywall-styled surface that shows the lost
/// streak as a dim "broken" flame and lets either partner buy it back. On success
/// it dismisses; the streak flame on the screen behind re-ignites at the restored
/// count.
struct StreakRestoreView: View {
    @State private var viewModel: StreakRestoreViewModel
    var onClose: () -> Void = {}

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(viewModel: StreakRestoreViewModel, onClose: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space24) {
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

            actions
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaSurfacePrimary)
        .task { await viewModel.load() }
        .onChange(of: viewModel.restoredCount) { _, count in
            if count != nil { onClose() }
        }
        .onChange(of: viewModel.error) { _, error in
            showBanner(for: error)
        }
    }

    private var actions: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: restore) {
                if viewModel.isPurchasing {
                    ProgressView().tint(.paeoniaTextInverse)
                } else {
                    Text(verbatim: buyTitle)
                }
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(viewModel.isPurchasing)

            Button(action: onClose) {
                Text(.streakRestoreNotNow)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
            .disabled(viewModel.isPurchasing)
        }
    }

    private var buyTitle: String {
        let base = String(localized: .streakRestoreBuyButton)
        guard let price = viewModel.priceText else { return base }
        return "\(base) · \(price)"
    }

    private func restore() {
        // Success dismisses via the `restoredCount` change handler above.
        Task { _ = await viewModel.purchase() }
    }

    private func showBanner(for error: StreakRestoreError?) {
        guard let error else { return }
        bannerCenter.show(.error(message: error.message))
        viewModel.clearError()
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
