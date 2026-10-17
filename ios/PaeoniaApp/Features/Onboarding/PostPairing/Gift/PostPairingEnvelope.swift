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

/// The sealed envelope from the daily question card (`PaeoniaEnvelopeLayer`), holding
/// `card`. Sized from `side`, the side of the square the card fills once it is out.
/// The card sits between the pink inside and the pocket and slides out of the pocket,
/// and the flap moves behind the card once it is past upright.
struct PostPairingEnvelope<Card: View>: View {
    let side: CGFloat
    let stage: PostPairingEnvelopeStage
    /// The idle float while it waits to be opened, from 0 to 1.
    var float: CGFloat = 0
    @ViewBuilder let card: Card

    private var width: CGFloat { side * 0.9 }
    /// The envelope sits low in the square, so the open flap and the card fit above it.
    private var envelopeY: CGFloat { side * 0.12 }

    var body: some View {
        ZStack {
            glow
                .offset(y: envelopeY)
                .zIndex(-1)

            PaeoniaEnvelopeLayer(part: .inside, width: width)
                .opacity(stage >= .flapOpening ? 1 : 0)
                .modifier(leaving)
                .zIndex(0)

            PaeoniaEnvelopeLayer(part: .flap(isOpen: stage >= .flapOpening), width: width)
                .modifier(leaving)
                .zIndex(stage >= .cardInside ? 1 : 4)

            cardLayer
                .zIndex(stage >= .cardFull ? 6 : 2)

            // The uncut art while it is closed, so no seam shows where the pieces
            // meet. It goes at once when the flap starts to move.
            PaeoniaEnvelopeLayer(part: .uncut, width: width)
                .opacity(stage >= .flapOpening ? 0 : 1)
                .transaction { $0.animation = nil }
                .modifier(leaving)
                .zIndex(3.5)

            PaeoniaEnvelopeLayer(part: .pocket, width: width)
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
