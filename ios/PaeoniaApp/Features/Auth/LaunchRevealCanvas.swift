import QuartzCore
import SwiftUI
import UIKit

/// The launch intro's plum canvas and petal mark, animated with Core Animation so
/// the render server plays the reveal. `LaunchExperienceView` decides when it starts.
///
/// The reveal starts no sooner than 400 ms after the canvas goes on screen, once iOS has
/// faded its launch screen out, and Core Animation then plays every frame of it. The
/// callbacks follow the animation's own clock.
struct LaunchRevealCanvas: UIViewRepresentable {
    enum Reveal: Equatable {
        /// The petals part while a hole opens from the center and grows past the corners.
        case opening
        /// Reduce Motion fades the whole canvas instead.
        case fading
    }

    let reveal: Reveal?
    /// The opening hole reached the screen's left and right edges.
    let onSidesUncovered: () -> Void
    /// The reveal or the fade has played out, or was cut off.
    let onFinished: () -> Void

    func makeUIView(context: Context) -> LaunchRevealCanvasView {
        LaunchRevealCanvasView()
    }

    func updateUIView(_ view: LaunchRevealCanvasView, context: Context) {
        view.onSidesUncovered = onSidesUncovered
        view.onFinished = onFinished
        switch reveal {
        case .opening:
            view.open()
        case .fading:
            view.fade()
        case nil:
            break
        }
    }
}

final class LaunchRevealCanvasView: UIView {
    // The composed mark matches the system launch screen's visible art exactly: the
    // `PaeoniaLaunchPetalMark` asset is a 150 pt square whose mark fills a centered
    // 124×62 region. The half assets share the full mark's viewBox, so overlaying
    // them at zero spread reproduces `PaeoniaMark` pixel for pixel.
    private static let markSize = CGSize(width: 124, height: 62)
    /// How far each half travels outward during the reveal.
    private static let revealSpread: CGFloat = 100
    private static let revealDuration: CFTimeInterval = 0.35
    private static let fadeDuration: CFTimeInterval = 0.22
    /// The petals start fast and settle, so they visibly part before the hole reaches them.
    private static let petalTiming = CAMediaTimingFunction(controlPoints: 0.3, 0.8, 0.3, 1)
    /// The hole starts slowly and speeds up, catching the petals about 70 ms in and
    /// cutting them away over the next 45 ms. It clears the corners around 290 ms.
    private static let holeTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.3, 1)
    private static let holeCurve = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.4, y: 0),
        endControlPoint: UnitPoint(x: 0.3, y: 1)
    )

    /// iOS crossfades its launch screen into the app's first frames over about 320 ms.
    /// The launch screen shows this same mark, so while it fades, a reveal under it shows
    /// the mark standing still over the parting petals and the opening hole.
    private static let launchScreenFade: CFTimeInterval = 0.4

    var onSidesUncovered: () -> Void = {}
    var onFinished: () -> Void = {}

    private let leftPetal = UIImageView(image: UIImage(resource: .paeoniaMarkPetalLeft))
    private let rightPetal = UIImageView(image: UIImage(resource: .paeoniaMarkPetalRight))
    private var requested: LaunchRevealCanvas.Reveal?
    private var hasStarted = false
    /// When the canvas first went on screen, roughly when the launch screen started to fade.
    private var shownAt: CFTimeInterval?
    private var isWaitingForLaunchScreen = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Color.paeoniaBackgroundPrimary)
        for petal in [leftPetal, rightPetal] {
            petal.contentMode = .scaleAspectFit
            addSubview(petal)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for petal in [leftPetal, rightPetal] {
            petal.bounds.size = Self.markSize
            petal.center = center
        }
        layer.mask?.frame = bounds
        startIfReady()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, shownAt == nil {
            shownAt = CACurrentMediaTime()
        }
        startIfReady()
    }

    func open() {
        request(.opening)
    }

    func fade() {
        request(.fading)
    }

    /// Reduce Motion can turn on while the reveal waits or plays, and then the fade wins.
    private func request(_ reveal: LaunchRevealCanvas.Reveal) {
        guard requested != .fading else { return }
        if reveal == .fading, hasStarted, requested == .opening {
            requested = .fading
            startFade()
            return
        }
        requested = reveal
        startIfReady()
    }

    /// Starts the requested reveal once the canvas has its size and the launch screen
    /// has faded out. Home builds its first frame meanwhile, behind the still mark.
    private func startIfReady() {
        guard let requested, !hasStarted, !bounds.isEmpty, let shownAt else { return }
        let wait = shownAt + Self.launchScreenFade - CACurrentMediaTime()
        guard wait <= 0 else {
            guard !isWaitingForLaunchScreen else { return }
            isWaitingForLaunchScreen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.isWaitingForLaunchScreen = false
                self?.startIfReady()
            }
            return
        }
        hasStarted = true
        switch requested {
        case .opening:
            startOpening()
        case .fading:
            startFade()
        }
    }

    private func startFade() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = Self.fadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.delegate = AnimationEnd { [weak self] in self?.onFinished() }
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
    }

    /// The hole is centered on the canvas, so it waits for the canvas's size.
    private func startOpening() {
        part(leftPetal.layer, by: -Self.revealSpread)
        part(rightPetal.layer, by: Self.revealSpread)

        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.fillRule = .evenOdd
        let fullDiameter = hypot(bounds.width, bounds.height) + 2
        // Just past the furthest corner, so no lit sliver survives the overlay's removal.
        let open = canvasPath(holeDiameter: fullDiameter)
        mask.path = open
        let hole = CABasicAnimation(keyPath: "path")
        hole.fromValue = canvasPath(holeDiameter: 0.01)
        hole.toValue = open
        hole.duration = Self.revealDuration
        hole.timingFunction = Self.holeTiming
        hole.delegate = AnimationEnd { [weak self] in self?.onFinished() }
        mask.add(hole, forKey: "hole")

        // Ends when the hole reaches the left and right edges: about 120 ms in on a
        // phone and 150 ms on an iPad. It starts with the hole, on the same clock.
        let sides = CABasicAnimation(keyPath: "opacity")
        sides.fromValue = 1
        sides.toValue = 1
        sides.duration = Self.holeCurve.inverse.value(at: bounds.width / fullDiameter) * Self.revealDuration
        sides.delegate = AnimationEnd { [weak self] in self?.onSidesUncovered() }
        mask.add(sides, forKey: "sides")
        layer.mask = mask
    }

    private func part(_ petal: CALayer, by offset: CGFloat) {
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = 0
        move.toValue = offset
        move.duration = Self.revealDuration
        move.timingFunction = Self.petalTiming
        petal.transform = CATransform3DMakeTranslation(offset, 0, 0)
        petal.add(move, forKey: "part")
    }

    /// The whole canvas with a circular hole of `holeDiameter` cut from its center.
    private func canvasPath(holeDiameter: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: CGRect(
            x: bounds.midX - holeDiameter / 2,
            y: bounds.midY - holeDiameter / 2,
            width: holeDiameter,
            height: holeDiameter
        ))
        return path
    }
}

/// Calls `action` once an animation stops, whether it played out or was removed,
/// for example when the app goes to the background.
private final class AnimationEnd: NSObject, CAAnimationDelegate {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        action()
    }
}
