import SwiftUI
import UIKit

/// The picture on the sign-in step, sized to the space it gets: the first drawing on a
/// widget tile when one waits to be kept, otherwise the welcome peonies. Neither grows
/// past its natural size.
struct WelcomeSignInPicture: View {
    /// What the picture shows.
    enum Content {
        /// The waiting drawing is still being drawn into an image.
        case loadingDrawing
        case drawing(UIImage)
        case hero
    }

    let content: Content

    /// `WelcomeHero`'s fixed canvas.
    private static let heroSize = CGSize(width: 330, height: 250)
    /// About the size of a large widget, so the tile reads as one.
    private static let maxTileSide: CGFloat = 300

    var body: some View {
        GeometryReader { proxy in
            picture(in: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func picture(in size: CGSize) -> some View {
        switch content {
        case .loadingDrawing:
            Color.clear
        case let .drawing(image):
            drawingTile(image, side: min(size.width, size.height, Self.maxTileSide))
        case .hero:
            WelcomeHero()
                .scaleEffect(min(1, size.width / Self.heroSize.width, size.height / Self.heroSize.height))
        }
    }

    private func drawingTile(_ image: UIImage, side: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(DrawingCanvasShape())
            .padding(PaeoniaSpacing.space12)
            .frame(width: side, height: side)
            .homeWidgetCardSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.welcomeSignInDrawingAccessibility))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("welcome.signIn.drawing")
    }
}

#if DEBUG
#Preview {
    WelcomeSignInPicture(content: .drawing(UIImage(resource: .placeholderSketch)))
        .frame(height: 340)
        .padding()
        .background(PaeoniaGlowBackground())
        .preferredColorScheme(.dark)
}
#endif
