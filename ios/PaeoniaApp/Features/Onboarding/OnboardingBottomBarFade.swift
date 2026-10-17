import SwiftUI

extension View {
    /// Puts the screen background behind a pinned bottom bar, with a short fade at its
    /// top edge, so content that scrolls under the bar doesn't show through its buttons.
    /// The fade has a fixed height, so a tall bar at large text sizes stays solid.
    func onboardingBottomBarFade() -> some View {
        background {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.paeoniaBackgroundPrimary.opacity(0), .paeoniaBackgroundPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: PaeoniaSpacing.space12)

                Color.paeoniaBackgroundPrimary
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
