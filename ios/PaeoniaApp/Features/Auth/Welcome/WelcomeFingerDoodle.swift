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
    @State private var committed: WelcomeCarriedDoodle?
    @State private var activeStroke: InkStroke?
    @State private var image: UIImage?

    init(doodle: Binding<WelcomeCarriedDoodle?>, onFirstTouch: @escaping () -> Void) {
        _doodle = doodle
        self.onFirstTouch = onFirstTouch
        // Reflow can recreate the illustration. Keep prior strokes in the same
        // carried drawing rather than restarting an unobserved local stroke list.
        _committed = State(initialValue: doodle.wrappedValue)
    }

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
            .task(id: side) {
                if side > 0, committed != nil { render(side: side) }
            }
            .onChange(of: doodle) { _, latest in
                guard activeStroke == nil else { return }
                committed = latest
                render(side: side)
            }
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
        if committed == nil, activeStroke == nil {
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
        let added = WelcomeCarriedDoodle(
            drawing: PKDrawing(strokes: [activeStroke.pencilKitStroke()]), canvasSide: side
        )
        let combined = committed?.adding(added) ?? added
        committed = combined
        self.activeStroke = nil
        doodle = combined
        render(side: side)
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
        let base = committed.map { $0.drawing.scaled(fromSide: $0.canvasSide, toSide: side) } ?? PKDrawing()
        let drawing = PKDrawing(strokes: base.strokes + [activeStroke].compactMap { $0?.pencilKitStroke() })
        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: displayScale)
        }
        image = rendered
    }
}
