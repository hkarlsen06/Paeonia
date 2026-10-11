import SwiftUI

/// The plum background of the welcome screen and the screens before pairing, with a soft petal
/// glow from the top as ambient light. Static, so it is comfortable with Reduce
/// Motion and never competes with the content. Screens that follow each other use
/// it so only their content changes between them.
struct PaeoniaGlowBackground: View {
    var body: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary

            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.16), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
