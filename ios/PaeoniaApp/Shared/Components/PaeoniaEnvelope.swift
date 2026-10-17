import SwiftUI

/// One layer of the daily card's sealed envelope (`HomeEnvelopeSealed`), cut along the
/// flap's rim so the flap can fold back and a letter can sit in the pocket. Each layer
/// fills the envelope's frame, `width` wide. The open flap reaches above the frame.
///
/// Stack them as inside, flap, letter, pocket, with the flap in front of the letter
/// until it has folded past upright. Show `uncut` over the pieces while the envelope is
/// closed, so no seam shows where they meet.
struct PaeoniaEnvelopeLayer: View {
    enum Part {
        /// The whole art, for the closed envelope.
        case uncut
        /// The pink inside, seen once the flap is open.
        case inside
        /// Everything below the flap's rim.
        case pocket
        case flap(isOpen: Bool)
    }

    /// The art's width over its height.
    static let aspect: CGFloat = 900 / 498

    let part: Part
    let width: CGFloat

    private var height: CGFloat { width / Self.aspect }

    var body: some View {
        switch part {
        case .uncut:
            art(clippedTo: Rectangle())
        case .inside:
            inside
        case .pocket:
            art(clippedTo: EnvelopePocketShape())
        case let .flap(isOpen):
            flap(isOpen: isOpen)
        }
    }

    private func art(clippedTo shape: some Shape) -> some View {
        Image(.homeEnvelopeSealed)
            .resizable()
            .frame(width: width, height: height)
            .clipShape(shape)
            .accessibilityHidden(true)
    }

    /// Square at the top and as wide as the open flap, so the sides run straight
    /// through the fold. Only as tall as the opening above the pocket, so it never
    /// peeks out around the art's rounded bottom corners.
    private var inside: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.paeoniaAccentPrimary, .paeoniaAccentPrimary.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // The shade under the fold, so the open flap reads as folded back.
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.3)
                )
            }
            .frame(width: width, height: height * 0.7)
            .frame(height: height, alignment: .top)
            .accessibilityHidden(true)
    }

    private func flap(isOpen: Bool) -> some View {
        art(clippedTo: EnvelopeFlapShape())
            // The back of the flap, which shows as it folds past upright. Opaque, so the
            // art's rounded corners don't show through at the fold.
            .overlay {
                EnvelopeFlapShape()
                    .fill(Color.paeoniaAccentPrimary)
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
}

/// The envelope with `letter` in its pocket, for art that only opens: closed, then the
/// flap folds back, then the letter shows above the pocket once the flap is behind it.
/// Position the letter with an offset from the envelope's center.
struct PaeoniaEnvelope<Letter: View>: View {
    let width: CGFloat
    /// The flap is folding back, or folded back.
    let isOpen: Bool
    /// The flap is past upright, so it sits behind the letter and the letter shows.
    let isFlapBehind: Bool
    @ViewBuilder let letter: Letter

    var body: some View {
        ZStack {
            PaeoniaEnvelopeLayer(part: .inside, width: width)
                .opacity(isOpen ? 1 : 0)
                .zIndex(0)
            PaeoniaEnvelopeLayer(part: .flap(isOpen: isOpen), width: width)
                .zIndex(isFlapBehind ? 1 : 4)
            letter
                .opacity(isFlapBehind ? 1 : 0)
                .zIndex(2)
            PaeoniaEnvelopeLayer(part: .pocket, width: width)
                .zIndex(3)
            // It goes at once when the flap starts to move.
            PaeoniaEnvelopeLayer(part: .uncut, width: width)
                .opacity(isOpen ? 0 : 1)
                .transaction { $0.animation = nil }
                .zIndex(5)
        }
        .frame(width: width, height: width / PaeoniaEnvelopeLayer.aspect)
    }
}

/// Where the flap's rim runs in the art, as fractions of its height: from near the
/// top corners down to the tip in the middle. Measured on the asset's pixels.
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

/// A plain sheet of paper for an envelope's pocket.
struct PaeoniaEnvelopeLetter: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
            .fill(Color.paeoniaMemory)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Closed and open") {
    VStack(spacing: PaeoniaSpacing.space40) {
        PaeoniaEnvelope(width: 240, isOpen: false, isFlapBehind: false) {
            PaeoniaEnvelopeLetter(width: 150, height: 120)
        }
        PaeoniaEnvelope(width: 240, isOpen: true, isFlapBehind: true) {
            PaeoniaEnvelopeLetter(width: 150, height: 120)
                .offset(y: -20)
        }
    }
    .padding(PaeoniaSpacing.space40)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
