import QuartzCore
import SwiftUI
import UIKit

/// The launch intro's plum canvas and petal mark, animated with Core Animation so
/// the render server plays the reveal. `LaunchExperienceView` decides when it starts.
///
/// Core Animation starts an animation when the update that added it is drawn. The
/// first surface builds in that same update, so the reveal waits behind the still
/// mark and then plays every frame. The callbacks follow the animation's own clock.
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

    var onSidesUncovered: () -> Void = {}
    var onFinished: () -> Void = {}

    private let leftPetal = UIImageView(image: UIImage(resource: .paeoniaMarkPetalLeft))
    private let rightPetal = UIImageView(image: UIImage(resource: .paeoniaMarkPetalRight))
    private var wantsOpen = false
    private var hasOpened = false
    private var hasFaded = false

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
        startOpeningIfLaidOut()
    }

    func open() {
        wantsOpen = true
        startOpeningIfLaidOut()
    }

    func fade() {
        guard !hasFaded else { return }
        hasFaded = true
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
    private func startOpeningIfLaidOut() {
        guard wantsOpen, !hasOpened, !hasFaded, !bounds.isEmpty else { return }
        hasOpened = true

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
