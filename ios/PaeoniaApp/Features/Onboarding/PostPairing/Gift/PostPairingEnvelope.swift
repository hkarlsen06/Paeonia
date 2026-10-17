import SwiftUI

/// Where the envelope's opening has got to. Each stage keeps the ones before it.
enum PostPairingEnvelopeStage: Int, Comparable {
    case sealed
    /// The envelope jumped at the tap.
    case unsealed
    /// The flap is folding back. It still covers the card.
    case flapOpening
    /// The flap is behind the card, which shows inside the envelope.
    case cardInside
    /// The card slid up out of the pocket.
    case cardOut
    /// The card grew to full size and the envelope dropped away.
    case cardFull

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The sealed envelope from the daily question card, holding `card`. Sized from
/// `side`, the side of the square the card fills once it is out. The art is cut
/// along the flap's rim into the flap and the front pocket, so the flap can fold
/// back and the card can slide out of the pocket. The card sits between the pink
/// inside and the pocket, and the flap moves behind the card once it is past upright.
struct PostPairingEnvelope<Card: View>: View {
    let side: CGFloat
    let stage: PostPairingEnvelopeStage
    /// The idle float while it waits to be opened, from 0 to 1.
    var float: CGFloat = 0
    @ViewBuilder let card: Card

    /// The art's width over its height.
    private static var artAspect: CGFloat { 900 / 498 }

    private var width: CGFloat { side * 0.9 }
    private var height: CGFloat { width / Self.artAspect }
    /// The envelope sits low in the square, so the open flap and the card fit above it.
    private var envelopeY: CGFloat { side * 0.12 }
    private var cornerRadius: CGFloat { height * 0.08 }

    var body: some View {
        ZStack {
            glow
                .offset(y: envelopeY)
                .zIndex(-1)

            inside
                .modifier(leaving)
                .zIndex(0)

            flap
                .modifier(leaving)
                .zIndex(stage >= .cardInside ? 1 : 4)

            cardLayer
                .zIndex(stage >= .cardFull ? 6 : 2)

            art(clippedTo: EnvelopePocketShape())
                // The cut pieces carry no shadow of their own, so the pocket casts it.
                .shadow(color: .black.opacity(0.35), radius: side * 0.05, y: side * 0.03)
                .modifier(leaving)
                .zIndex(3)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// The float while waiting, the jump at the tap, then the drop as the card comes out.
    private var leaving: EnvelopeLeaving {
        EnvelopeLeaving(
            isGone: stage >= .cardFull,
            offset: envelopeY - float * side * 0.03,
            drop: side * 0.16,
            scale: stage == .unsealed ? 1.05 : 1
        )
    }

    // MARK: Layers

    private var glow: some View {
        // Breathes with the float, so the gift feels alive.
        RadialGradient(
            colors: [.paeoniaAccentPrimary.opacity(stage >= .cardFull ? 0 : 0.22 + 0.06 * float), .clear],
            center: .center,
            startRadius: side * 0.1,
            endRadius: side * 0.65
        )
        .frame(width: side * 1.5, height: side * 1.5)
        .allowsHitTesting(false)
    }

    private func art(clippedTo shape: some Shape) -> some View {
        Image(.homeEnvelopeSealed)
            .resizable()
            .frame(width: width, height: height)
            .clipShape(shape)
            .accessibilityHidden(true)
    }

    /// The pink inside, seen once the flap is open.
    private var inside: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.paeoniaAccentPrimary, .paeoniaAccentPrimary.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Only as tall as the opening above the pocket, and a hair narrower than
            // the art, so it never peeks out around the art's rounded edges.
            .frame(width: width * 0.99, height: height * 0.7)
            .frame(height: height, alignment: .top)
    }

    private var flap: some View {
        let isOpen = stage >= .flapOpening
        return art(clippedTo: EnvelopeFlapShape())
            // The back of the flap, which shows as it folds past upright.
            .overlay {
                EnvelopeFlapShape()
                    .fill(Color.paeoniaAccentPrimary.opacity(0.85))
                    .frame(width: width, height: height)
                    .opacity(isOpen ? 1 : 0)
            }
            .rotation3DEffect(
                .degrees(isOpen ? 178 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.5
            )
            // Overlaps the body a hair when open, so no gap shows at the fold.
            .offset(y: isOpen ? height * 0.01 : 0)
    }

    private var cardLayer: some View {
        card
            // Pale paper while it is in the envelope, so it reads as a letter. It
            // turns into the canvas as it grows.
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .fill(Color.paeoniaMemory)
                    .opacity(stage >= .cardFull ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .scaleEffect(stage >= .cardFull ? 1 : 0.45)
            .offset(y: cardOffset)
            // Hidden until the flap is out of the way, so it never shows through it.
            .opacity(stage >= .cardInside ? 1 : 0)
    }

    private var cardOffset: CGFloat {
        switch stage {
        case .sealed, .unsealed, .flapOpening, .cardInside: envelopeY + side * 0.02
        case .cardOut: envelopeY - side * 0.22
        case .cardFull: 0
        }
    }
}

/// Moves a part of the envelope with the idle float and the jump, then drops and
/// fades it once the card is out.
private struct EnvelopeLeaving: ViewModifier {
    let isGone: Bool
    let offset: CGFloat
    let drop: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: isGone ? offset + drop : offset)
            .scaleEffect(isGone ? 0.92 : 1)
            // Faster than the drop, so it is gone before it reaches the square's edge.
            .animation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)) {
                $0.opacity(isGone ? 0 : 1)
            }
    }
}

/// Where the flap's rim runs in the art, as fractions of its height: from near the
/// top corners down to the tip in the middle.
nonisolated private enum EnvelopeRim {
    static let cornerY: CGFloat = 0.09
    static let tipY: CGFloat = 0.635
}

/// The flap: the top edge down to the tip, rim included.
nonisolated private struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * EnvelopeRim.cornerY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * EnvelopeRim.tipY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * EnvelopeRim.cornerY))
        path.closeSubpath()
        return path
    }
}

/// The front pocket: everything below the flap's rim.
nonisolated private struct EnvelopePocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * EnvelopeRim.cornerY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * EnvelopeRim.tipY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * EnvelopeRim.cornerY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Stages") {
    ScrollView {
        VStack(spacing: PaeoniaSpacing.space24) {
            ForEach([PostPairingEnvelopeStage.sealed, .cardInside, .cardOut], id: \.self) { stage in
                PostPairingEnvelope(side: 240, stage: stage) {
                    GameSquare(side: 240) { Color.clear }
                }
            }
        }
        .padding()
    }
    .background(PaeoniaGlowBackground())
    .preferredColorScheme(.dark)
}
#endif
