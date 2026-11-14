import PencilKit
import UIKit

/// Two stacked PencilKit canvases that take no touches. PencilKit draws again
/// everything on a canvas whenever its drawing is set. The lower canvas holds
/// the strokes that rarely change and the upper one the few that change on
/// every frame, so a frame only draws the upper canvas again.
final class LayeredCanvasView: UIView {
    /// The strokes that rarely change, and over them the strokes in progress.
    var lowerDrawing = PKDrawing() {
        didSet { show(lowerDrawing, on: lowerCanvas, or: lowerPicture) }
    }
    var upperDrawing = PKDrawing() {
        didSet { show(upperDrawing, on: upperCanvas, or: upperPicture) }
    }
    /// Below 1 while a view around this one shows it smaller (`GameChatStageZoom`).
    ///
    /// A PencilKit canvas can go blank when a view around it scales it. While this view
    /// is scaled it shows pictures of its two drawings instead, and it goes back to the
    /// canvases once it is at full size again.
    var surroundingScale: CGFloat = 1 {
        didSet {
            guard surroundingScale != oldValue else { return }
            canvasReturn?.cancel()
            if surroundingScale == 1 {
                canvasReturn = Task { [weak self] in await self?.returnToCanvases() }
            } else {
                showPictures()
            }
        }
    }
    /// Called after the size may have changed.
    var onLayout: (() -> Void)?

    private let lowerCanvas = LayeredCanvasView.makeCanvas()
    private let upperCanvas = LayeredCanvasView.makeCanvas()
    private let lowerPicture = UIImageView()
    private let upperPicture = UIImageView()
    private var showsPictures = false
    private var canvasReturn: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [lowerCanvas, upperCanvas, lowerPicture, upperPicture] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
        setShowsPictures(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    private func show(_ drawing: PKDrawing, on canvas: PKCanvasView, or picture: UIImageView) {
        guard showsPictures else {
            canvas.drawing = drawing
            return
        }
        let side = min(bounds.width, bounds.height)
        guard side > 0, !drawing.strokes.isEmpty else {
            picture.image = nil
            return
        }
        let scale = traitCollection.displayScale
        // The canvases paint in light mode too (`configureForPaeoniaDrawingCanvas`).
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            picture.image = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: scale)
        }
    }

    private func setShowsPictures(_ showsPictures: Bool) {
        self.showsPictures = showsPictures
        lowerCanvas.isHidden = showsPictures
        upperCanvas.isHidden = showsPictures
        lowerPicture.isHidden = !showsPictures
        upperPicture.isHidden = !showsPictures
    }

    private func showPictures() {
        setShowsPictures(true)
        show(lowerDrawing, on: lowerCanvas, or: lowerPicture)
        show(upperDrawing, on: upperCanvas, or: upperPicture)
    }

    /// Gives the canvases the drawings as they are now, once the view shows at full size
    /// again. A view that has left the window goes back without waiting.
    private func returnToCanvases() async {
        try? await Task.sleep(for: .seconds(PaeoniaMotion.motionMorph))
        while !Task.isCancelled, isShownScaled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !Task.isCancelled else { return }
        setShowsPictures(false)
        lowerCanvas.drawing = lowerDrawing
        upperCanvas.drawing = upperDrawing
        lowerPicture.image = nil
        upperPicture.image = nil
    }

    private var isShownScaled: Bool {
        guard bounds.width > 0, window != nil else { return false }
        return abs(convert(bounds, to: nil).width / bounds.width - 1) > 0.001
    }

    private static func makeCanvas() -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.configureForPaeoniaDrawingCanvas()
        canvasView.isUserInteractionEnabled = false
        return canvasView
    }
}

extension CADisplayLink {
    /// Drawing a canvas again on every frame of a 120 Hz screen costs more than
    /// it shows.
    func capDrawingFrameRate() {
        preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    }
}
