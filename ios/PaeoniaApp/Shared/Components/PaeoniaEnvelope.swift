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
                // The pocket's rim casts a little shade on the letter and the lining.
                .shadow(color: .black.opacity(0.28), radius: width * 0.012, y: -width * 0.006)
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

    /// The lining seen through the opening above the pocket, in the shade of the open
    /// flap. It reaches only a little below the pocket's rim, so it never shows through
    /// the art's soft edges.
    private var inside: some View {
        EnvelopeOpeningShape()
            .fill(Color.paeoniaAccentSecondary)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.26), .black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: EnvelopeRim.tipY)
                )
                .clipShape(EnvelopeOpeningShape())
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private func flap(isOpen: Bool) -> some View {
        art(clippedTo: EnvelopeFlapShape())
            // The back of the flap, which shows as it folds past upright. Opaque, so the
            // front's art doesn't show through.
            .overlay {
                flapBack
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

    /// Paper lined with pink, leaving a border of paper along the edges, like a lined
    /// envelope. Drawn upside down, since the fold turns it over: the fold is at the top
    /// and the tip at the bottom.
    private var flapBack: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaAccentSecondary, .paeoniaAccentPrimary],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: EnvelopeRim.tipY)
            )
            // The shade where the lining bends at the fold.
            LinearGradient(
                colors: [.black.opacity(0.22), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: EnvelopeRim.cornerY * 2.5)
            )
            // The clip keeps the inner half of the stroke. The fold gets no border, so
            // the lining runs on into the envelope.
            EnvelopeFlapEdges()
                .stroke(Color.paeoniaEnvelopePaper, style: StrokeStyle(lineWidth: width * 0.07, lineJoin: .round))
        }
        .frame(width: width, height: height)
        .clipShape(EnvelopeFlapShape())
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
            // It goes at once when the flap starts to move. Only that change skips the
            // animation, so the layer still moves with the others when the envelope does.
            PaeoniaEnvelopeLayer(part: .uncut, width: width)
                .opacity(isOpen ? 0 : 1)
                .transaction(value: isOpen) { $0.animation = nil }
                .zIndex(5)
        }
        .frame(width: width, height: width / PaeoniaEnvelopeLayer.aspect)
    }
}

/// Where the flap's rim runs in the art, as fractions of its height: from near the
/// top corners down to the rounded tip in the middle. Measured on the asset's pixels.
nonisolated private enum EnvelopeRim {
    static let cornerY: CGFloat = 0.09
    /// Where the rim's straight edges would meet. The tip's curve passes 0.635 down.
    static let tipY: CGFloat = 0.665
    static let tipRadius: CGFloat = 0.163
    /// How far the lining reaches below the rim, out of sight behind the pocket.
    static let insideOverlap: CGFloat = 0.06

    /// From the left corner, round the tip, to the right corner, `drop` lower.
    static func addRim(to path: inout Path, in rect: CGRect, drop: CGFloat = 0) {
        let y = { (fraction: CGFloat) in rect.minY + rect.height * (fraction + drop) }
        path.addLine(to: CGPoint(x: rect.minX, y: y(cornerY)))
        path.addArc(
            tangent1End: CGPoint(x: rect.midX, y: y(tipY)),
            tangent2End: CGPoint(x: rect.maxX, y: y(cornerY)),
            radius: rect.height * tipRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: y(cornerY)))
    }
}

/// The flap: the top edge down to the tip, rim included.
nonisolated private struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        EnvelopeRim.addRim(to: &path, in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The flap's cut edges, the sides and the rim, without the fold.
nonisolated private struct EnvelopeFlapEdges: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        EnvelopeRim.addRim(to: &path, in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The opening above the pocket, reaching a little under its rim.
nonisolated private struct EnvelopeOpeningShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        EnvelopeRim.addRim(to: &path, in: rect, drop: EnvelopeRim.insideOverlap)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The front pocket: everything below the flap's rim.
nonisolated private struct EnvelopePocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        EnvelopeRim.addRim(to: &path, in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A sheet of paper for an envelope's pocket, with a small heart near its top that
/// shows above the pocket.
struct PaeoniaEnvelopeLetter: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
            .fill(Color.paeoniaEnvelopePaper)
            .overlay(alignment: .top) {
                Image(systemName: "heart.fill")
                    .resizable()
                    .accessibilityHidden(true)
                    .scaledToFit()
                    .foregroundStyle(.paeoniaAccentSecondary)
                    .frame(width: width * 0.17)
                    .padding(.top, height * 0.16)
            }
            .shadow(color: .black.opacity(0.18), radius: width * 0.03, y: width * 0.015)
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
