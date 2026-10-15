import PencilKit
import UIKit

/// Two stacked PencilKit canvases that take no touches. PencilKit draws again
/// everything on a canvas whenever its drawing is set. The lower canvas holds
/// the strokes that rarely change and the upper one the few that change on
/// every frame, so a frame only draws the upper canvas again.
final class LayeredCanvasView: UIView {
    let lowerCanvas = LayeredCanvasView.makeCanvas()
    let upperCanvas = LayeredCanvasView.makeCanvas()
    /// Called after the size may have changed.
    var onLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        for canvas in [lowerCanvas, upperCanvas] {
            canvas.frame = bounds
            canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(canvas)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
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
