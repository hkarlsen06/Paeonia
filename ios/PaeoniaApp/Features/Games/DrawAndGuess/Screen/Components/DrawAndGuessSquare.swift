import PencilKit
import SwiftUI

/// The square surface every drawing sits on. It has the ink color of the widget
/// canvas, so a saved drawing looks like a widget drawing.
struct DrawAndGuessSquare<Content: View>: View {
    let side: CGFloat
    /// 1 while playing, 0.8 on the result.
    var scale: CGFloat = 1
    /// The soft glow behind the square on the reveal, 0 for none.
    var glow: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: side, height: side)
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                    .allowsHitTesting(false)
            }
            .background {
                RadialGradient(
                    colors: [.paeoniaAccentPrimary.opacity(glow), .clear],
                    center: .center,
                    startRadius: side * 0.2,
                    endRadius: side * 0.85
                )
                .frame(width: side * 1.7, height: side * 1.7)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .scaleEffect(scale)
            .frame(width: side * scale, height: side * scale)
    }
}

/// A finished drawing, all of it, on a canvas that takes no touches.
struct DrawAndGuessStaticDrawing: UIViewRepresentable {
    let drawing: PKDrawing

    func makeUIView(context _: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.isUserInteractionEnabled = false
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context _: Context) {
        canvasView.drawing = drawing
    }
}

/// The canonical drawing scaled to the square it is shown in.
struct DrawAndGuessFinalDrawingView: View {
    let drawing: DrawAndGuessFinalDrawing?
    let side: CGFloat

    var body: some View {
        DrawAndGuessStaticDrawing(drawing: drawing?.fitted(toSide: side) ?? PKDrawing())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A small picture of a finished drawing, for the pending save row.
struct DrawAndGuessThumbnail: View {
    let drawing: DrawAndGuessFinalDrawing?
    var side: CGFloat = 48
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: drawing?.drawing.strokes.count) {
            guard let drawing else { return }
            image = Self.render(drawing.drawing, side: side, displayScale: displayScale)
        }
    }

    private static func render(_ drawing: PKDrawing, side: CGFloat, displayScale: CGFloat) -> UIImage {
        let canonical = DrawAndGuessCanvas.canonicalSide
        let bounds = CGRect(x: 0, y: 0, width: canonical, height: canonical)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: displayScale * side / canonical)
        }
        return image
    }
}
