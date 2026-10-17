import SwiftUI

/// The screens between sign-in and the paired app.
enum RootFramedScreen: Hashable {
    case onboarding
    case paywall
    case pairing
    /// Joining a partner through their code, in place of the paywall or pairing.
    case join
    case relationshipEnded
    case accountClosed
    case deletingAccount
}

/// The frame those screens share: the brand lockup on top and the screen's own
/// content filling the rest. The lockup stays in place while the content under it
/// changes from one step to the next.
struct RootBrandedFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        // No navigation bar: one that comes and goes with a screen's toolbar
        // would move the lockup.
        VStack(spacing: PaeoniaSpacing.sectionSpacing) {
            PaeoniaBrandLockup(
                wordmarkSize: 36,
                taglineSize: 17,
                taglineColor: .paeoniaTextSecondary
            )
            .frame(maxWidth: .infinity)
            // Drops in only as the cold-launch intro uncovers it. Mid-session it
            // is already where the welcome screen's lockup was.
            .launchEntrance(order: 0)

            ZStack(alignment: .top) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The same column as the welcome screen, so the flow keeps one width on iPad.
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PaeoniaGlowBackground())
    }
}
