import SwiftUI

/// Where the envelope's opening has got to. Each stage keeps the ones before it.
enum PostPairingEnvelopeStage: Int, Comparable {
    case sealed
    /// The seal popped off.
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

/// A pale envelope with a pink seal, holding `card`. Sized from `side`, the side of
/// the square the card fills once it is out. The card sits between the envelope's
/// back and its front pocket, so it slides out of it, and the flap moves behind the
/// card once it has folded past upright.
struct PostPairingEnvelope<Card: View>: View {
    let side: CGFloat
    let stage: PostPairingEnvelopeStage
    /// The idle float while it waits to be opened, from 0 to 1.
    var float: CGFloat = 0
    @ViewBuilder let card: Card

    private var width: CGFloat { side * 0.9 }
    private var height: CGFloat { width * 0.66 }
    private var flapHeight: CGFloat { height * 0.58 }
    private var sealSize: CGFloat { side * 0.17 }
    private var cornerRadius: CGFloat { side * 0.05 }

    var body: some View {
        ZStack {
            glow
                .zIndex(-1)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.paeoniaAccentPrimary)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.35), radius: side * 0.05, y: side * 0.03)
                .modifier(leaving)
                .zIndex(0)

            flap
                .modifier(leaving)
                .zIndex(stage >= .cardInside ? 1 : 4)

            cardLayer
                .zIndex(stage >= .cardFull ? 6 : 2)

            pocket
                .modifier(leaving)
                .zIndex(3)

            seal
                .modifier(leaving)
                .zIndex(5)
        }
        .frame(width: side, height: side)
    }

    /// The float while waiting, then the drop as the card comes out.
    private var leaving: EnvelopeLeaving {
        // A short drop, so the envelope fades out inside the square instead of
        // sliding over the title under it.
        EnvelopeLeaving(isGone: stage >= .cardFull, offset: -float * side * 0.03, drop: side * 0.16)
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

    private var pocket: some View {
        EnvelopePocketShape()
            .fill(Color.paeoniaMemory)
            .overlay {
                EnvelopePocketShape(foldsOnly: true)
                    .stroke(Color.paeoniaAccentPrimary.opacity(0.35), lineWidth: 1)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var flap: some View {
        EnvelopeFlapShape()
            .fill(
                LinearGradient(
                    colors: [.paeoniaMemory, .paeoniaMemory.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                EnvelopeFlapShape()
                    .stroke(Color.paeoniaAccentPrimary.opacity(0.35), lineWidth: 1)
            }
            .frame(width: width, height: flapHeight)
            .rotation3DEffect(
                .degrees(stage >= .flapOpening ? 178 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.5
            )
            .offset(y: (flapHeight - height) / 2)
    }

    private var seal: some View {
        let isPopped = stage >= .unsealed
        return ZStack {
            Circle()
                .fill(Color.paeoniaAccentSecondary)
            Circle()
                .strokeBorder(Color.paeoniaTextPrimary.opacity(0.45), lineWidth: max(1, sealSize * 0.05))
                .padding(sealSize * 0.12)
            Image(systemName: "heart.fill")
                .font(.system(size: sealSize * 0.38, weight: .bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityHidden(true)
        }
        .frame(width: sealSize, height: sealSize)
        .shadow(color: .black.opacity(0.25), radius: sealSize * 0.12, y: sealSize * 0.06)
        .scaleEffect(isPopped ? 1.5 : 1)
        .opacity(isPopped ? 0 : 1)
        .offset(y: flapHeight - height / 2)
    }

    private var cardLayer: some View {
        card
            .scaleEffect(stage >= .cardFull ? 1 : 0.5)
            .offset(y: cardOffset)
            // Hidden until the flap is out of the way, so it never shows through it.
            .opacity(stage >= .cardInside ? 1 : 0)
    }

    private var cardOffset: CGFloat {
        switch stage {
        case .sealed, .unsealed, .flapOpening, .cardInside: side * 0.06
        case .cardOut: -side * 0.2
        case .cardFull: 0
        }
    }
}

/// Moves a part of the envelope with the idle float, then drops and fades it once
/// the card is out.
private struct EnvelopeLeaving: ViewModifier {
    let isGone: Bool
    let offset: CGFloat
    let drop: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(y: isGone ? drop : offset)
            .scaleEffect(isGone ? 0.92 : 1)
            // Faster than the drop, so it is gone before it reaches the square's edge.
            .animation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)) {
                $0.opacity(isGone ? 0 : 1)
            }
    }
}

/// The front of the envelope: the bottom and sides, with the V of the folds.
nonisolated private struct EnvelopePocketShape: Shape {
    /// Only the two fold lines, for a stroke over the fill.
    var foldsOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.32))
        guard !foldsOnly else {
            return path
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The flap: a triangle from the top edge down to the seal.
nonisolated private struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
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
