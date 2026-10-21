import PencilKit
import SwiftUI

extension ExquisiteCorpseRevealContent {
    /// The finished creature as one tall picture, head on top. Nil until all three
    /// drawings are on the phone.
    var shareable: PaeoniaShareable? {
        guard isReady else { return nil }
        let drawings = drawings
        let title = String(localized: .exquisiteCorpseRevealNumber(number))
        return PaeoniaShareable(title: title) {
            let order: [ExquisiteCorpsePartKind] = [.head, .body, .legs]
            let images = order.compactMap { kind in
                drawings[kind].flatMap {
                    PaeoniaShareRenderer.inkImage(
                        of: $0,
                        canvasSide: GameCanvas.canonicalSide,
                        pixelSide: ExquisiteCorpseShareCard.pixelSide
                    )
                }
            }
            guard images.count == order.count else { return nil }
            return PaeoniaShareRenderer.png(
                PaeoniaShareCardFrame(title: title, subtitle: String(localized: .exquisiteCorpseName)) {
                    ExquisiteCorpseShareCard(parts: images)
                }
            )
        }
    }
}

/// The three parts stacked with no gap on one plum canvas, with a hairline at each
/// fold, like the finished figure in the game.
private struct ExquisiteCorpseShareCard: View {
    let parts: [UIImage]

    /// A part is narrower than the card, so the figure fits on a phone screen
    /// when it is sent on.
    static let side: CGFloat = 232
    static let pixelSide: CGFloat = side * 3
    private static let hairline: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            ForEach(parts.indices, id: \.self) { index in
                Image(uiImage: parts[index])
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.side, height: Self.side)
                    .accessibilityHidden(true)
            }
        }
        .background(.paeoniaBackgroundPrimary)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                ForEach(Array(1..<max(parts.count, 2)), id: \.self) { index in
                    Rectangle()
                        .fill(.paeoniaTextTertiary.opacity(0.3))
                        .frame(height: Self.hairline)
                        .offset(y: Self.side * CGFloat(index) - Self.hairline / 2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeEmphasis)
        }
    }
}
