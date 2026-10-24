import SwiftUI

/// The frame of every signed-out step after welcome: the glow background, the welcome
/// screen's column and margins, and no lockup. The logo shows on the welcome screen
/// only, so these steps use the whole height. Back sits at the top of each step's
/// content with no padding above it, level with the drawing screen's back button, so
/// it stays in one place from step to step.
struct WelcomeStepFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PaeoniaGlowBackground())
    }
}
