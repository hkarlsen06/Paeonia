import PencilKit
import UIKit

/// What a touch on the canvas does.
enum CanvasTool: Equatable {
    /// A pen or pencil stroke, drawn by `PaeoniaDrawingCanvasView` itself.
    case ink(InkStyle)
    /// A tap fills the area under it.
    case fill
    /// PencilKit's own pixel eraser.
    case eraser(width: CGFloat)

    var pencilKitTool: any PKTool {
        switch self {
        case let .ink(style):
            PKInkingTool(style.kind.inkType, color: style.color, width: style.width)
        case .fill:
            PKInkingTool(.monoline)
        case let .eraser(width):
            PKEraserTool(.fixedWidthBitmap, width: width)
        }
    }
}

/// A pen or pencil stroke on the canvas, as it is drawn.
enum InkEvent {
    case began(InkStroke)
    case changed(InkStroke)
    /// The finger held still and the stroke turned into a clean shape, or it
    /// moved on and the shape turned back into what was drawn.
    case snapChanged(InkStroke)
    /// The stroke is finished. Sent just before it is added to the drawing.
    case ended(InkStroke)
}

/// A PencilKit canvas whose drawing starts `overscanTop` points below its top
/// edge. Strokes drawn above that have a negative y.
class OverscanCanvasView: PKCanvasView {
    /// The canvas is scrolled up by this much, so the drawing's y 0 sits this
    /// far below the view's top edge.
    var overscanTop: CGFloat = 0 {
        didSet {
            guard overscanTop != oldValue else { return }
            contentInsetAdjustmentBehavior = .never
            contentInset.top = overscanTop
            contentOffset = CGPoint(x: 0, y: -overscanTop)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A layout pass may move the offset back to the content's top.
        let pinned = CGPoint(x: 0, y: -overscanTop)
        if overscanTop > 0, contentOffset != pinned {
            contentOffset = pinned
        }
    }
}

/// The drawing canvas. It has no PencilKit undo stack, because the view models
/// keep their own (`DrawingEditHistory`) and PencilKit's would undo to drawings
/// that are gone.
///
/// Pen and pencil strokes do not use PencilKit's drawing gesture. This view
/// collects the touches into an `InkStroke`, shows it on a canvas on top while
/// the finger is down, and adds the finished stroke to `drawing` on lift. That
/// fires `canvasViewDrawingDidChange` like a PencilKit stroke, so the host
/// records it as one undo step. The eraser stays PencilKit's.
///
/// When the finger holds still at the end of a stroke, the stroke turns into
/// the clean shape it looks like (`ShapeRecognizer`) while the finger is still
/// down. A still finger sends no touches, so a display link checks the hold,
/// and only while a stroke is open. Slow drawing can read as a hold, so the
/// stroke keeps every touch after a snap and turns back into them when the
/// finger moves on (`InkStroke.unsnapIfMovedAway`).
///
/// The wet canvas on top and this canvas draw the stroke from the same
/// `PKStroke`, so nothing moves at lift. The wet canvas hides in the same
/// frame this canvas first shows the stroke. Hiding it later, when
/// `canvasViewDidFinishRendering` came, left a frame with both, and pencil
/// ink flashed brighter. `PaeoniaDrawingCanvasContainer` puts the wet canvas
/// on top.
final class PaeoniaDrawingCanvasView: OverscanCanvasView {
    private static let minimumSampleSpacing: CGFloat = 0.75

    override var undoManager: UndoManager? { nil }

    var canvasTool: CanvasTool = .fill {
        didSet {
            if canvasTool != oldValue {
                // Only the eraser draws with PencilKit's tool. The others set
                // a matching one, so PencilKit's state matches the screen.
                tool = canvasTool.pencilKitTool
            }
            applyInputMode()
        }
    }

    /// A tap with the paint bucket, in canvas points.
    var onFill: (CGPoint) -> Void = { _ in }
    /// A pen or pencil stroke started or ended. PencilKit reports the eraser
    /// through its delegate.
    var onInkStrokeInProgressChange: (Bool) -> Void = { _ in }

    /// A finger or pencil is drawing or erasing right now.
    var isStrokeInProgress: Bool {
        if stroke != nil {
            return true
        }
        switch drawingGestureRecognizer.state {
        case .began, .changed:
            return true
        default:
            return false
        }
    }

    override var overscanTop: CGFloat {
        didSet { wetCanvas.overscanTop = overscanTop }
    }

    fileprivate let wetCanvas = WetInkCanvas()
    private let inkRecognizer = InkGestureRecognizer()
    private let fillTap = UITapGestureRecognizer()
    private var inkObservers: [(InkEvent) -> Void] = []
    /// The stroke under the finger.
    private var stroke: InkStroke?
    private var strokeStartTimestamp: TimeInterval = 0
    private var hold = HoldDetector()
    private var holdLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureForPaeoniaDrawingCanvas()
        inkRecognizer.onBegan = { [weak self] touch, event in self?.inkBegan(touch, event: event) }
        inkRecognizer.onMoved = { [weak self] touch, event in self?.inkMoved(touch, event: event) }
        inkRecognizer.onEnded = { [weak self] touch, event in self?.inkEnded(touch, event: event) }
        addGestureRecognizer(inkRecognizer)
        fillTap.addTarget(self, action: #selector(fillTapped))
        addGestureRecognizer(fillTap)
        tool = canvasTool.pencilKitTool
        applyInputMode()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addInkObserver(_ observer: @escaping (InkEvent) -> Void) {
        inkObservers.append(observer)
    }

    /// Which recognizer takes the touches. Runs on every update, because
    /// setting PencilKit's tool can turn its drawing gesture back on.
    func applyInputMode() {
        switch canvasTool {
        case .ink:
            drawingGestureRecognizer.isEnabled = false
            inkRecognizer.isEnabled = true
            fillTap.isEnabled = false
        case .fill:
            // The drawing gesture is turned off, not `isDrawingEnabled`. With
            // `isDrawingEnabled` off, the canvas did not redraw the filled
            // drawing until much later.
            drawingGestureRecognizer.isEnabled = false
            inkRecognizer.isEnabled = false
            fillTap.isEnabled = true
        case .eraser:
            drawingGestureRecognizer.isEnabled = true
            inkRecognizer.isEnabled = false
            fillTap.isEnabled = false
        }
    }

    @objc private func fillTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onFill(recognizer.location(in: self))
    }

    // MARK: Ink

    private func inkBegan(_ touch: UITouch, event _: UIEvent) {
        guard case let .ink(style) = canvasTool else { return }
        strokeStartTimestamp = touch.timestamp
        let newStroke = InkStroke(style: style, first: sample(touch))
        stroke = newStroke
        startHoldCheck(at: touch.preciseLocation(in: self), time: touch.timestamp)
        // Shown and drawn in one go, so the last stroke never shows again here.
        wetCanvas.isHidden = false
        wetCanvas.drawing = PKDrawing(strokes: [newStroke.pencilKitStroke()])
        wetCanvas.layoutIfNeeded()
        notify(.began(newStroke))
        onInkStrokeInProgressChange(true)
    }

    private func inkMoved(_ touch: UITouch, event: UIEvent) {
        guard var current = stroke else { return }
        let added = newSamples(touch, event: event, after: current)
        for sample in added {
            hold.add(sample.location, at: strokeStartTimestamp + sample.timeOffset)
        }
        current.append(added)
        let didUnsnap = current.unsnapIfMovedAway()
        stroke = current
        if didUnsnap, let last = current.samples.last {
            startHoldCheck(at: last.location, time: strokeStartTimestamp + last.timeOffset)
        }
        let predicted = (event.predictedTouches(for: touch) ?? []).map(sample)
        wetCanvas.drawing = PKDrawing(strokes: [current.pencilKitStroke(predicted: predicted)])
        notify(didUnsnap ? .snapChanged(current) : .changed(current))
    }

    /// Lift or cancel. A cancelled stroke (the system took the touch, or an
    /// Apple Pencil double tap switched tools) keeps what was drawn so far.
    private func inkEnded(_ touch: UITouch?, event: UIEvent?) {
        guard var finished = stroke else { return }
        stopHoldCheck()
        if let touch, let event {
            finished.append(newSamples(touch, event: event, after: finished))
            _ = finished.unsnapIfMovedAway()
        }
        stroke = nil
        notify(.ended(finished))
        drawing.strokes.append(finished.pencilKitStroke())
        // The flush shows the stroke here in the same frame the wet canvas hides.
        CATransaction.flush()
        wetCanvas.isHidden = true
        wetCanvas.drawing = PKDrawing()
        onInkStrokeInProgressChange(false)
    }

    // MARK: Snap to shape

    private func startHoldCheck(at location: CGPoint, time: TimeInterval) {
        stopHoldCheck()
        hold = HoldDetector()
        hold.add(location, at: time)
        let link = CADisplayLink(target: self, selector: #selector(checkHold))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        holdLink = link
    }

    private func stopHoldCheck() {
        holdLink?.invalidate()
        holdLink = nil
    }

    /// Snaps the stroke once the finger has held still long enough. A stroke
    /// that looks like no shape stays as drawn, and the same hold is not
    /// tried again.
    @objc private func checkHold() {
        guard var current = stroke, let deadline = hold.deadline, CACurrentMediaTime() >= deadline else {
            return
        }
        guard let shape = ShapeRecognizer.recognize(current.samples.map(\.location)) else {
            hold.disarmUntilMoved()
            return
        }
        stopHoldCheck()
        current.snap(to: shape, at: CACurrentMediaTime() - strokeStartTimestamp)
        stroke = current
        wetCanvas.drawing = PKDrawing(strokes: [current.pencilKitStroke()])
        PaeoniaHaptics.shapeSnapped()
        notify(.snapChanged(current))
    }

    /// The touch's coalesced samples that moved far enough to matter. Closer
    /// samples add nothing visible and only make the stroke bigger.
    private func newSamples(_ touch: UITouch, event: UIEvent, after stroke: InkStroke) -> [InkSample] {
        var last = stroke.samples[stroke.samples.count - 1].location
        var kept: [InkSample] = []
        for coalesced in event.coalescedTouches(for: touch) ?? [touch] {
            let next = sample(coalesced)
            if hypot(next.location.x - last.x, next.location.y - last.y) >= Self.minimumSampleSpacing {
                kept.append(next)
                last = next.location
            }
        }
        return kept
    }

    private func sample(_ touch: UITouch) -> InkSample {
        InkSample(
            location: touch.preciseLocation(in: self),
            timeOffset: touch.timestamp - strokeStartTimestamp,
            force: touch.type == .pencil ? touch.force : nil,
            azimuth: touch.azimuthAngle(in: self),
            altitude: touch.altitudeAngle
        )
    }

    private func notify(_ event: InkEvent) {
        for observer in inkObservers {
            observer(event)
        }
    }
}

/// The drawing canvas with its wet canvas on top. The two are siblings. With
/// the wet canvas inside the drawing canvas, PencilKit drew none of the
/// drawing canvas's changes in most app sessions.
final class PaeoniaDrawingCanvasContainer: UIView {
    let canvas = PaeoniaDrawingCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [canvas, canvas.wetCanvas] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Shows the stroke under the finger, over the canvas. It takes no touches.
private final class WetInkCanvas: OverscanCanvasView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureForPaeoniaDrawingCanvas()
        isUserInteractionEnabled = false
        drawingGestureRecognizer.isEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Follows the first touch on the canvas from touch down to lift. Other
/// touches are ignored.
private final class InkGestureRecognizer: UIGestureRecognizer {
    var onBegan: (UITouch, UIEvent) -> Void = { _, _ in }
    var onMoved: (UITouch, UIEvent) -> Void = { _, _ in }
    /// The touch and event at lift, or nil when the touch was cancelled.
    var onEnded: (UITouch?, UIEvent?) -> Void = { _, _ in }

    private var trackedTouch: UITouch?

    init() {
        super.init(target: nil, action: nil)
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else {
            for touch in touches where touch !== trackedTouch {
                ignore(touch, for: event)
            }
            return
        }
        trackedTouch = touch
        state = .began
        onBegan(touch, event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .changed
        onMoved(trackedTouch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        trackedTouch = nil
        onEnded(touch, event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        trackedTouch = nil
        onEnded(nil, nil)
        state = .cancelled
    }

    /// Turning the recognizer off mid-stroke resets it without
    /// `touchesCancelled`.
    override func reset() {
        super.reset()
        if trackedTouch != nil {
            trackedTouch = nil
            onEnded(nil, nil)
        }
    }
}

extension PKCanvasView {
    func configureForPaeoniaDrawingCanvas() {
        backgroundColor = .clear
        drawingPolicy = .anyInput
        isOpaque = false
        isScrollEnabled = false
        overrideUserInterfaceStyle = .light
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
    }
}
