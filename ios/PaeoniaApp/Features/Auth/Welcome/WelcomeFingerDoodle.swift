import PencilKit
import SwiftUI

/// A small surprise on the welcome widget: a finger on the canvas draws, in the app's
/// own pen (`InkStroke`, drawn by PencilKit like a saved drawing) and the palette's
/// blush ink. Strokes add up while the welcome screen shows, and each lifted stroke
/// updates `doodle`. Start our space takes the doodle to the first drawing
/// (`WelcomeFlowModel.chooseStart(carrying:)`). Otherwise it goes when the screen does.
/// The first touch calls `onFirstTouch`, so the tile can clear its note.
///
/// The drag starts at once, so it does not wait to see whether the welcome screen's
/// scroll view wants it. It covers the canvas only.
struct WelcomeFingerDoodle: View {
    @Binding var doodle: WelcomeCarriedDoodle?
    let onFirstTouch: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var strokes: [InkStroke] = []
    @State private var activeStroke: InkStroke?
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width

            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .accessibilityHidden(true)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        draw(value, side: side)
                    }
                    .onEnded { _ in
                        lift(side: side)
                    }
            )
        }
    }

    private func draw(_ value: DragGesture.Value, side: CGFloat) {
        if strokes.isEmpty, activeStroke == nil {
            onFirstTouch()
        }
        if var stroke = activeStroke {
            stroke.append([sample(value, since: stroke.creationDate)])
            activeStroke = stroke
        } else {
            activeStroke = InkStroke(
                style: Self.pen(side: side),
                first: sample(value, since: value.time),
                creationDate: value.time
            )
        }
        render(side: side)
    }

    private func lift(side: CGFloat) {
        guard let activeStroke else {
            return
        }
        strokes.append(activeStroke)
        self.activeStroke = nil
        render(side: side)
        doodle = WelcomeCarriedDoodle(
            drawing: PKDrawing(strokes: strokes.map { $0.pencilKitStroke() }),
            canvasSide: side
        )
    }

    private func sample(_ value: DragGesture.Value, since start: Date) -> InkSample {
        InkSample(
            location: value.location,
            timeOffset: value.time.timeIntervalSince(start),
            force: nil,
            azimuth: 0,
            altitude: 0
        )
    }

    /// The real pen in the palette's blush, at the note's felt-tip width for a canvas
    /// `side` points wide. The pen draws twice its width.
    private static func pen(side: CGFloat) -> InkStyle {
        InkStyle(
            kind: .pen,
            color: .paeoniaWidgetDrawing,
            width: side / 95,
            lineStyle: .solid
        )
    }

    /// Draws every stroke so far, in light mode as the saved drawings are, so
    /// PencilKit keeps the ink's own color.
    private func render(side: CGFloat) {
        let drawn = strokes + [activeStroke].compactMap(\.self)
        let drawing = PKDrawing(strokes: drawn.map { $0.pencilKitStroke() })
        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: displayScale)
        }
        image = rendered
    }
}
