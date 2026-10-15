import SwiftUI

/// The soft light behind the top of every tab's first screen. Pink from the left and lavender
/// from the right, the same two lights as the Games room (`GameHubBackdrop`), meeting in the
/// middle. Both fade out to the plain plum by half the screen's height. Quiet on purpose: it
/// shows around the cards and behind the top bar. Every tab draws the same light in the same
/// place, so switching tabs leaves it still.
struct PaeoniaTabBackdrop: View {
    /// How far down the light reaches, as a share of the screen height.
    private static let reach: CGFloat = 0.5
    private static let glowOpacity = 0.22

    var body: some View {
        ZStack(alignment: .top) {
            Color.paeoniaBackgroundPrimary
            GeometryReader { proxy in
                ZStack {
                    glow(.paeoniaAccentPrimary, from: .topLeading)
                    glow(.paeoniaInkLavender, from: .topTrailing)
                }
                .frame(height: proxy.size.height * Self.reach)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// An ellipse of light centered on a top corner. The stops ease out, so the edge
    /// doesn't show as a line.
    private func glow(_ color: Color, from corner: UnitPoint) -> some View {
        EllipticalGradient(
            stops: [
                .init(color: color.opacity(Self.glowOpacity), location: 0),
                .init(color: color.opacity(Self.glowOpacity * 0.6), location: 0.25),
                .init(color: color.opacity(Self.glowOpacity * 0.28), location: 0.5),
                .init(color: color.opacity(Self.glowOpacity * 0.08), location: 0.75),
                .init(color: color.opacity(0), location: 1),
            ],
            center: corner,
            startRadiusFraction: 0,
            endRadiusFraction: 1
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
