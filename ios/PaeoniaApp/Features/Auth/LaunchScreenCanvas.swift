import QuartzCore
import SwiftUI
import UIKit

/// The system launch screen drawn again: `LaunchBackground` with `PaeoniaLaunchPetalMark`
/// centered at its own size, as `UILaunchScreen` in Info.plist shows them. Setting
/// `isFading` fades it out with Core Animation. Without the mark it is the plain app
/// background, which has the same color.
///
/// The first app surface builds in the same update that starts the fade, which took
/// 80 to 117 ms on an iPhone. A SwiftUI animation would lose that much of the fade.
/// Core Animation starts the fade when that update is drawn and plays all of it.
struct LaunchScreenCanvas: UIViewRepresentable {
    var showsMark = true
    let isFading: Bool
    /// The fade has played out, or was cut off.
    let onFaded: () -> Void

    func makeUIView(context: Context) -> LaunchScreenCanvasView {
        LaunchScreenCanvasView(showsMark: showsMark)
    }

    func updateUIView(_ view: LaunchScreenCanvasView, context: Context) {
        view.onFaded = onFaded
        if isFading {
            view.fade()
        }
    }
}

final class LaunchScreenCanvasView: UIView {
    var onFaded: () -> Void = {}
    private var hasFaded = false

    init(showsMark: Bool) {
        super.init(frame: .zero)
        backgroundColor = UIColor(resource: .launchBackground)
        guard showsMark else { return }
        let mark = UIImageView(image: UIImage(resource: .paeoniaLaunchPetalMark))
        mark.contentMode = .center
        mark.frame = bounds
        mark.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(mark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func fade() {
        guard !hasFaded else { return }
        hasFaded = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = PaeoniaMotion.motionDefault
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.delegate = FadeEnd { [weak self] in self?.onFaded() }
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
    }
}

/// Calls `action` once the fade stops, whether it played out or was removed, for
/// example when the app goes to the background.
private final class FadeEnd: NSObject, CAAnimationDelegate {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        action()
    }
}
