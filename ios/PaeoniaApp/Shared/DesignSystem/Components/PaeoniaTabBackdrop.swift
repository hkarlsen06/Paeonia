import SwiftUI

/// The soft light behind the top of every tab's first screen, on the plain plum. Every tab
/// draws the same light in the same place, so switching tabs leaves it still.
struct PaeoniaTabBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.paeoniaBackgroundPrimary
            GeometryReader { proxy in
                PaeoniaTabLight()
                    .frame(height: proxy.size.height * PaeoniaTabLight.reach)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Pink from the left and lavender from the right, the same two lights as the Games room
/// (`GameHubBackdrop`), meeting in the middle. Quiet on purpose: it shows around the cards
/// and behind the top bar. Home's map draws it over itself, so the Us tab has it too.
struct PaeoniaTabLight: View {
    /// How far down the light reaches, as a share of the screen height.
    static let reach: CGFloat = 0.5
    var strength = 0.22
    /// Where the glows sit, and how far they reach as a share of the frame. A frame drawn
    /// past the screen's edges moves them onto the screen's corners.
    var leadingCorner = UnitPoint.topLeading
    var trailingCorner = UnitPoint.topTrailing
    var radiusFraction: CGFloat = 1

    var body: some View {
        ZStack {
            glow(.paeoniaAccentPrimary, from: leadingCorner)
            glow(.paeoniaBackdropGlow, from: trailingCorner)
        }
    }

    /// An ellipse of light centered on a top corner. The stops ease out, so the edge
    /// doesn't show as a line.
    private func glow(_ color: Color, from corner: UnitPoint) -> some View {
        EllipticalGradient(
            stops: [
                .init(color: color.opacity(strength), location: 0),
                .init(color: color.opacity(strength * 0.6), location: 0.25),
                .init(color: color.opacity(strength * 0.28), location: 0.5),
                .init(color: color.opacity(strength * 0.08), location: 0.75),
                .init(color: color.opacity(0), location: 1),
            ],
            center: corner,
            startRadiusFraction: 0,
            endRadiusFraction: radiusFraction
        )
    }
}

extension View {
    /// Puts the tabs' shared light behind a tab's first screen. Use it instead of the plain
    /// screen background, since an opaque background inside would cover it.
    func paeoniaTabBackdrop() -> some View {
        background { PaeoniaTabBackdrop() }
    }
}

#Preview {
    PaeoniaTabBackdrop()
}
