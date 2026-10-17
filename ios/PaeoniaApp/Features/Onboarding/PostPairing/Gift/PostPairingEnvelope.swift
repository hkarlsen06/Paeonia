import SwiftUI

/// Where the envelope's opening has got to. Each stage keeps the ones before it.
enum PostPairingEnvelopeStage: Int, Comparable {
    case sealed
    /// The envelope jumped at the tap.
    case unsealed
    /// The card's top shows above the envelope.
    case cardPeeking
    /// The card slid up out of the envelope.
    case cardOut
    /// The card grew to full size and the envelope dropped away.
    case cardFull

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The sealed envelope from the daily question card, holding `card`. Sized from
/// `side`, the side of the square the card fills once it is out. The card waits
/// behind the envelope and slides up out of its top edge, then grows in front of it.
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
    /// The envelope sits low in the square, so the card has room to come out above it.
    private var envelopeY: CGFloat { side * 0.14 }

    var body: some View {
        ZStack {
            glow
                .offset(y: envelopeY)
                .zIndex(-1)

            cardLayer
                .zIndex(stage >= .cardFull ? 2 : 0)

            Image(.homeEnvelopeSealed)
                .resizable()
                .aspectRatio(Self.artAspect, contentMode: .fit)
                .frame(width: width)
                .shadow(color: .black.opacity(0.35), radius: side * 0.05, y: side * 0.03)
                .scaleEffect(stage == .unsealed ? 1.06 : 1)
                .modifier(EnvelopeLeaving(
                    isGone: stage >= .cardFull,
                    offset: envelopeY - float * side * 0.03,
                    drop: side * 0.16
                ))
                .accessibilityHidden(true)
                .zIndex(1)
        }
        .frame(width: side, height: side)
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

    private var cardLayer: some View {
        card
            // Pale paper while it comes out of the envelope, so it reads as a letter
            // and not a dark hole. It turns into the canvas as it grows.
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .fill(Color.paeoniaMemory)
                    .opacity(stage >= .cardFull ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .scaleEffect(stage >= .cardFull ? 1 : 0.5)
            .offset(y: cardOffset)
            // Hidden until the envelope covers its lower part, so it never shows below it.
            .opacity(stage >= .cardPeeking ? 1 : 0)
    }

    /// Behind the envelope, then above it, then centered once full size.
    private var cardOffset: CGFloat {
        switch stage {
        case .sealed, .unsealed: envelopeY
        case .cardPeeking: envelopeY - side * 0.12
        case .cardOut: envelopeY - side * 0.3
        case .cardFull: 0
        }
    }
}

/// Moves the envelope with the idle float, then drops and fades it once the card
/// is out.
private struct EnvelopeLeaving: ViewModifier {
    let isGone: Bool
    let offset: CGFloat
    let drop: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(y: isGone ? offset + drop : offset)
            .scaleEffect(isGone ? 0.92 : 1)
            // Faster than the drop, so it is gone before it reaches the square's edge.
            .animation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)) {
                $0.opacity(isGone ? 0 : 1)
            }
    }
}

#if DEBUG
#Preview("Stages") {
    ScrollView {
        VStack(spacing: PaeoniaSpacing.space24) {
            ForEach([PostPairingEnvelopeStage.sealed, .cardPeeking, .cardOut], id: \.self) { stage in
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
