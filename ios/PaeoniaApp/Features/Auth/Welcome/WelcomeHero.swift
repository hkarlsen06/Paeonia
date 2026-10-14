import SwiftUI

/// The picture in the middle of the welcome screen: a pink and a lavender peony
/// leaning into each other, one for each partner. Each bloom casts a soft glow
/// in its own color, and a few loose petals drift around them, some sharp and
/// close, some blurred and far away. The pair sways and the petals drift
/// slowly. Under Reduce Motion everything holds still.
struct WelcomeHero: View {
    private struct Petal {
        let image: ImageResource
        let width: CGFloat
        /// Center of the petal in the canvas, as a fraction of its size.
        let center: UnitPoint
        let angle: Double
        let drift: CGSize
        let duration: TimeInterval
    }

    private static let canvas = CGSize(width: 330, height: 250)
    /// `WelcomePeonyPair` is 840 x 571 px.
    private static let pairSize = CGSize(width: 280, height: 280 / 1.471)

    /// Blurred and faded behind the pair, so the pair reads as the focus.
    private static let farPetals = [
        Petal(
            image: .welcomePetalLavender, width: 15, center: UnitPoint(x: 0.90, y: 0.10),
            angle: 30, drift: CGSize(width: -4, height: 6), duration: 6.5
        ),
        Petal(
            image: .welcomePetalPink, width: 12, center: UnitPoint(x: 0.10, y: 0.80),
            angle: -40, drift: CGSize(width: 3, height: 5), duration: 7.2
        ),
    ]

    private static let nearPetals = [
        Petal(
            image: .welcomePetalPink, width: 22, center: UnitPoint(x: 0.07, y: 0.20),
            angle: 15, drift: CGSize(width: -5, height: 8), duration: 5.4
        ),
        Petal(
            image: .welcomePetalRose, width: 17, center: UnitPoint(x: 0.95, y: 0.66),
            angle: -20, drift: CGSize(width: -6, height: 7), duration: 4.8
        ),
        Petal(
            image: .welcomePetalLavender, width: 19, center: UnitPoint(x: 0.80, y: 0.95),
            angle: 50, drift: CGSize(width: -4, height: 5), duration: 6.0
        ),
    ]

    var body: some View {
        ZStack {
            glow

            petals(Self.farPetals)
                .blur(radius: 1.2)
                .opacity(0.6)

            Image(.welcomePeonyPair)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: Self.pairSize.width, height: Self.pairSize.height)
                // Sways from the crossed stems, like a flower in a light breeze.
                .modifier(WelcomeDrift(offset: .zero, turn: 1.2, anchor: .bottom, duration: 6))

            petals(Self.nearPetals)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .accessibilityHidden(true)
    }

    /// One soft light behind each bloom, in the bloom's own color.
    private var glow: some View {
        ZStack {
            bloomGlow(.paeoniaAccentPrimary, x: -0.2)
            bloomGlow(.paeoniaInkLavender, x: 0.22)
        }
        .blur(radius: 40)
    }

    private func bloomGlow(_ color: Color, x: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.38))
            .frame(width: 170, height: 170)
            .offset(x: Self.pairSize.width * x, y: -10)
    }

    private func petals(_ petals: [Petal]) -> some View {
        ForEach(petals.indices, id: \.self) { index in
            let petal = petals[index]

            Image(petal.image)
                .resizable()
                .accessibilityHidden(true)
                .scaledToFit()
                .frame(width: petal.width)
                .rotationEffect(.degrees(petal.angle))
                .modifier(WelcomeDrift(offset: petal.drift, turn: 12, anchor: .center, duration: petal.duration))
                .position(
                    x: Self.canvas.width * petal.center.x,
                    y: Self.canvas.height * petal.center.y
                )
        }
    }
}

/// A slow back-and-forth drift and turn. Each part gets its own duration so
/// nothing moves in step.
private struct WelcomeDrift: ViewModifier {
    let offset: CGSize
    /// Degrees turned between the two ends of the drift.
    let turn: Double
    let anchor: UnitPoint
    let duration: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifted = false

    func body(content: Content) -> some View {
        let side: CGFloat = reduceMotion ? 0 : isDrifted ? 0.5 : -0.5

        content
            .animation(reduceMotion ? nil : drift) {
                $0
                    .rotationEffect(.degrees(turn * side), anchor: anchor)
                    .offset(x: offset.width * side, y: offset.height * side)
            }
            .onAppear { isDrifted = true }
    }

    private var drift: Animation {
        PaeoniaMotion.standardCurve(duration: duration).repeatForever(autoreverses: true)
    }
}

#if DEBUG
#Preview {
    WelcomeHero()
        .padding()
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}
#endif
