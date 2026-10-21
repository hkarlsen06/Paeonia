import PencilKit
import SwiftUI

/// Turns SwiftUI cards and PencilKit drawings into pictures to share. Cards are
/// drawn with `ImageRenderer` at a fixed size, so a shared picture looks the same
/// on every phone and at every text size.
enum PaeoniaShareRenderer {
    /// The width of a card in points. At 3x it is 1,080 pixels wide.
    static let cardWidth: CGFloat = 360
    /// The room around the content inside a card.
    static let cardMargin: CGFloat = PaeoniaSpacing.space24
    /// The width the content has inside a card.
    static var contentWidth: CGFloat { cardWidth - cardMargin * 2 }

    /// Draws the card as a PNG. A very tall card (a long story) steps down to a
    /// smaller scale when the picture would be too large for the renderer.
    static func png(_ card: some View) -> PaeoniaShareImage? {
        let content = card
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.isOpaque = true
        for scale in [CGFloat(3), 2, 1] {
            renderer.scale = scale
            if let data = renderer.uiImage?.pngData() {
                return PaeoniaShareImage(data: data, format: .png)
            }
        }
        return nil
    }

    /// Draws a photo as a JPEG, with the card's content on top of it.
    static func jpeg(_ content: some View, pixelSize: CGSize) -> PaeoniaShareImage? {
        let renderer = ImageRenderer(content: content.frame(width: pixelSize.width, height: pixelSize.height))
        renderer.scale = 1
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.92) else { return nil }
        return PaeoniaShareImage(data: data, format: .jpeg)
    }

    /// The ink of a drawing on a transparent background, square, at the pixel
    /// size. The canvas is always light, so literal ink colors render as drawn.
    /// `canvasSide` is the side of the square the strokes were drawn in.
    static func inkImage(of drawing: PKDrawing, canvasSide: CGFloat, pixelSide: CGFloat = 1_080) -> UIImage? {
        guard canvasSide > 0, pixelSide > 0 else { return nil }
        let rect = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: pixelSide / canvasSide)
        }
        return image
    }
}
