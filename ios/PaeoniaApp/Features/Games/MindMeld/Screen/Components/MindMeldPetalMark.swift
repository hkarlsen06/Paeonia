import SwiftUI

/// Five rounded petals around a small center. It takes its size from the frame and
/// its color from the foreground style, so `.foregroundStyle(.paeoniaAccentPrimary)`
/// tints it. It is a picture, so VoiceOver skips it.
struct MindMeldPetalMark: View {
    var body: some View {
        MindMeldPetalShape()
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// The petals as one path, so a translucent tint does not darken where they touch.
struct MindMeldPetalShape: Shape {
    private static let petalCount = 5

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // One petal pointing up from the center. The others are turned copies.
        let petal = Path(ellipseIn: CGRect(x: -side * 0.14, y: -side * 0.48, width: side * 0.28, height: side * 0.4))
        var path = Path()
        for index in 0..<Self.petalCount {
            let turn = Double(index) * 2 * .pi / Double(Self.petalCount)
            let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: turn)
            path.addPath(petal, transform: transform)
        }
        let hub = side * 0.065
        path.addEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
        return path
    }
}

#if DEBUG
#Preview {
    HStack(spacing: PaeoniaSpacing.space24) {
        MindMeldPetalMark().frame(width: 16, height: 16).foregroundStyle(.paeoniaSuccess)
        MindMeldPetalMark().frame(width: 32, height: 32).foregroundStyle(.paeoniaAccentPrimary)
        MindMeldPetalMark().frame(width: 96, height: 96).foregroundStyle(.paeoniaAccentPrimary.opacity(0.4))
    }
    .padding()
    .background(.paeoniaBackgroundSecondary)
}
#endif
