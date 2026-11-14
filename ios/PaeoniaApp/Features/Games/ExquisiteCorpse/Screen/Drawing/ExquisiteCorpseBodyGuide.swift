import SwiftUI

/// A faint dashed outline of the part behind the drawer's ink: a head, a body,
/// legs or feet. It only helps the drawer see where the part sits. It is not in
/// the drawing, so it never reaches the strip, the partner, the reveal or the
/// history. It takes no touches, and VoiceOver skips it.
struct ExquisiteCorpseBodyGuide: View {
    let part: ExquisiteCorpsePartKind
    /// The canvas side.
    let side: CGFloat

    var body: some View {
        ExquisiteCorpseBodyGuideShape(part: part)
            .stroke(.paeoniaTextTertiary.opacity(0.45), style: Self.style)
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let style = StrokeStyle(
        lineWidth: PaeoniaRadius.strokeEmphasis,
        lineCap: .round,
        lineJoin: .round,
        dash: [6, 4]
    )
}

/// The outline of a part in its square. The parts meet at the same x positions
/// on each fold, so the outline of one part continues in the next: the neck
/// joins the head to the body, the hips the body to the legs, and the ankles
/// the legs to the feet. Every outline is symmetric, so each part draws its left
/// half and mirrors it.
nonisolated struct ExquisiteCorpseBodyGuideShape: Shape {
    let part: ExquisiteCorpsePartKind

    func path(in rect: CGRect) -> Path {
        Self.unitPath(for: part).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
        )
    }

    // The left edges of the joins, as a share of the side. The right edges mirror them.
    private static let neckX: CGFloat = 0.41
    private static let hipX: CGFloat = 0.30
    private static let ankleOuterX: CGFloat = 0.33
    private static let ankleInnerX: CGFloat = 0.43

    /// The outline in a square of side 1.
    static func unitPath(for part: ExquisiteCorpsePartKind) -> Path {
        switch part {
        case .head: head
        case .body: mirrored(bodyHalf)
        case .legs: mirrored(legsHalf)
        case .feet: mirrored(footHalf)
        }
    }

    private static var head: Path {
        let center = CGPoint(x: 0.5, y: 0.42)
        let radius = CGSize(width: 0.30, height: 0.32)
        var path = Path(ellipseIn: CGRect(
            x: center.x - radius.width,
            y: center.y - radius.height,
            width: radius.width * 2,
            height: radius.height * 2
        ))
        // The neck starts where it meets the bottom of the head.
        let offset = (neckX - center.x) / radius.width
        let chinY = center.y + radius.height * (1 - offset * offset).squareRoot()
        var neck = Path()
        neck.move(to: CGPoint(x: neckX, y: chinY))
        neck.addLine(to: CGPoint(x: neckX, y: 1))
        path.addPath(mirrored(neck))
        return path
    }

    /// The neck, a shoulder, an arm hanging down, and the side of the torso down to the hip.
    private static var bodyHalf: Path {
        var half = Path()
        half.move(to: CGPoint(x: neckX, y: 0))
        half.addLine(to: CGPoint(x: neckX, y: 0.08))
        half.addQuadCurve(to: CGPoint(x: 0.18, y: 0.16), control: CGPoint(x: 0.30, y: 0.09))
        half.addLine(to: CGPoint(x: 0.08, y: 0.58))
        half.addQuadCurve(to: CGPoint(x: 0.17, y: 0.58), control: CGPoint(x: 0.12, y: 0.66))
        half.addLine(to: CGPoint(x: 0.26, y: 0.28))
        half.addQuadCurve(to: CGPoint(x: hipX, y: 1), control: CGPoint(x: 0.24, y: 0.65))
        return half
    }

    /// One leg, from the hip and the crotch down to the ankle.
    private static var legsHalf: Path {
        var half = Path()
        half.move(to: CGPoint(x: hipX, y: 0))
        half.addQuadCurve(to: CGPoint(x: ankleOuterX, y: 1), control: CGPoint(x: 0.27, y: 0.5))
        half.move(to: CGPoint(x: 0.5, y: 0.2))
        half.addQuadCurve(to: CGPoint(x: ankleInnerX, y: 1), control: CGPoint(x: 0.47, y: 0.55))
        return half
    }

    /// One foot, from the ankle down to a toe that points outward.
    private static var footHalf: Path {
        var half = Path()
        half.move(to: CGPoint(x: ankleOuterX, y: 0))
        half.addLine(to: CGPoint(x: ankleOuterX, y: 0.58))
        half.addQuadCurve(to: CGPoint(x: 0.13, y: 0.70), control: CGPoint(x: 0.22, y: 0.60))
        half.addQuadCurve(to: CGPoint(x: 0.15, y: 0.84), control: CGPoint(x: 0.07, y: 0.80))
        half.addLine(to: CGPoint(x: 0.42, y: 0.84))
        half.addQuadCurve(to: CGPoint(x: ankleInnerX, y: 0.58), control: CGPoint(x: 0.47, y: 0.72))
        half.addLine(to: CGPoint(x: ankleInnerX, y: 0))
        return half
    }

    /// `half` and its mirror image across the middle of the square.
    private static func mirrored(_ half: Path) -> Path {
        var both = half
        both.addPath(half.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)))
        return both
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        ForEach(ExquisiteCorpsePartKind.allCases, id: \.self) { part in
            ExquisiteCorpseBodyGuide(part: part, side: 160)
        }
    }
    .background(.paeoniaBackgroundPrimary)
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
