import Observation
import SwiftUI
import UIKit

// The chat's swipe gestures, ported from Tidex's friends chat. A swipe on a bubble
// toward the middle replies to it, a swipe left anywhere else slides the bubbles over
// to show their times, and a swipe right goes back. Each gesture is a UIKit pan
// recognizer on the chat's table or cell, so it can decide on direction before the
// table's own scroll takes the touch.

enum ThreadChatSwipeDirection: Equatable {
    case left
    case right
}

enum ThreadChatReplySwipeOutcome: Equatable {
    case reset
    case trigger
}

enum ThreadChatPanGestureResolver {
    static let horizontalIntentRatio: CGFloat = 1.45
    static let navigationBackDistanceThreshold: CGFloat = 72
    static let navigationBackVelocityThreshold: CGFloat = 450

    static func hasPassedMinimumDistance(translation: CGSize, minimumDistance: CGFloat) -> Bool {
        hypot(translation.width, translation.height) >= minimumDistance
    }

    static func hasHorizontalIntent(velocity: CGSize, ratio: CGFloat = horizontalIntentRatio) -> Bool {
        abs(velocity.width) > abs(velocity.height) * ratio
    }

    static func hasDirectionalHorizontalIntent(
        velocity: CGSize,
        direction: ThreadChatSwipeDirection,
        ratio: CGFloat = horizontalIntentRatio
    ) -> Bool {
        guard hasHorizontalIntent(velocity: velocity, ratio: ratio) else { return false }
        switch direction {
        case .left: return velocity.width < 0
        case .right: return velocity.width > 0
        }
    }

    static func shouldTriggerNavigationBack(translation: CGSize, velocity: CGSize) -> Bool {
        guard translation.width > 0, abs(translation.width) > abs(translation.height) else { return false }
        return translation.width >= navigationBackDistanceThreshold
            || velocity.width >= navigationBackVelocityThreshold
    }
}

enum ThreadChatReplySwipeResolver {
    static let minimumDistance: CGFloat = 20
    static let actionThreshold: CGFloat = 0.4
    static let actionWidth: CGFloat = 80
    static let velocityThreshold: CGFloat = 300

    /// The bubble follows the finger up to the action width, then drags with resistance.
    static func clampedOffset(
        horizontal: CGFloat,
        vertical: CGFloat,
        allowedDirection: ThreadChatSwipeDirection
    ) -> CGFloat? {
        guard abs(horizontal) > abs(vertical) else { return nil }
        switch allowedDirection {
        case .left: guard horizontal < 0 else { return 0 }
        case .right: guard horizontal > 0 else { return 0 }
        }
        if abs(horizontal) > actionWidth {
            let excess = abs(horizontal) - actionWidth
            let sign: CGFloat = horizontal > 0 ? 1 : -1
            return sign * (actionWidth + excess * 0.3)
        }
        return horizontal
    }

    static func crossedThreshold(offset: CGFloat) -> Bool {
        abs(offset) >= actionWidth * actionThreshold
    }

    static func outcome(
        offset: CGFloat,
        velocity: CGFloat,
        allowedDirection: ThreadChatSwipeDirection
    ) -> ThreadChatReplySwipeOutcome {
        switch allowedDirection {
        case .left:
            offset < 0 && (crossedThreshold(offset: offset) || velocity < -velocityThreshold) ? .trigger : .reset
        case .right:
            offset > 0 && (crossedThreshold(offset: offset) || velocity > velocityThreshold) ? .trigger : .reset
        }
    }
}

/// How far the chat bubbles are slid over to show their times. The page and every row
/// share one. Only the rows read `offset`, so each drag frame redraws them and leaves
/// the page, and the chat rows built from it, alone.
@MainActor
@Observable
final class ThreadChatTimestampReveal {
    var offset: CGFloat = 0
}

enum ThreadChatTimestampRevealResolver {
    static let revealWidth: CGFloat = 64
    static let minimumDistance: CGFloat = 16

    /// The partner's bubbles stay this much narrower, so the times have room beside them.
    static func contentMaxWidth(baseWidth: CGFloat, isCurrentUser: Bool) -> CGFloat {
        isCurrentUser ? baseWidth : max(0, baseWidth - revealWidth)
    }

    static func clampedRevealOffset(horizontal: CGFloat, vertical: CGFloat) -> CGFloat? {
        guard abs(horizontal) > abs(vertical) else { return nil }
        guard horizontal < 0 else { return 0 }
        return min(abs(horizontal), revealWidth)
    }
}

struct ThreadChatDragValue {
    let translation: CGSize
    let velocity: CGSize
}

/// What a touch landed on, so the back gesture can leave a bubble's reply swipe alone.
enum ThreadChatGestureTargetKind {
    case replyPayload(direction: ThreadChatSwipeDirection)
    case timestampRevealGutter
}

/// An invisible marker view. It never takes touches, it only tells the gesture
/// bridges what lies under a point.
final class ThreadChatGestureTargetView: UIView {
    var kind: ThreadChatGestureTargetKind

    init(kind: ThreadChatGestureTargetKind) {
        self.kind = kind
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside _: CGPoint, with _: UIEvent?) -> Bool {
        false
    }
}

final class ThreadChatDirectionalPanRecognizer: UIPanGestureRecognizer {
    var targetKind: ThreadChatGestureTargetKind?
    var direction: ThreadChatSwipeDirection?
}

/// A horizontal pan over the view it overlays. The recognizer sits on the hosting
/// table cell, so it sees the touch before the table's scroll does.
struct ThreadChatHorizontalPanSurface: UIViewRepresentable {
    let targetKind: ThreadChatGestureTargetKind
    let minimumDistance: CGFloat
    let direction: ThreadChatSwipeDirection
    let onChanged: (ThreadChatDragValue) -> Void
    let onEnded: (ThreadChatDragValue) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            targetKind: targetKind,
            minimumDistance: minimumDistance,
            direction: direction,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = ThreadChatGestureTargetView(kind: targetKind)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? ThreadChatGestureTargetView)?.kind = targetKind
        context.coordinator.targetKind = targetKind
        context.coordinator.minimumDistance = minimumDistance
        context.coordinator.direction = direction
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var targetKind: ThreadChatGestureTargetKind
        var minimumDistance: CGFloat
        var direction: ThreadChatSwipeDirection
        var onChanged: (ThreadChatDragValue) -> Void
        var onEnded: (ThreadChatDragValue) -> Void
        private weak var view: UIView?
        private weak var gestureHostView: UIView?
        private var recognizer: ThreadChatDirectionalPanRecognizer?
        private var hasPassedMinimumDistance = false

        init(
            targetKind: ThreadChatGestureTargetKind,
            minimumDistance: CGFloat,
            direction: ThreadChatSwipeDirection,
            onChanged: @escaping (ThreadChatDragValue) -> Void,
            onEnded: @escaping (ThreadChatDragValue) -> Void
        ) {
            self.targetKind = targetKind
            self.minimumDistance = minimumDistance
            self.direction = direction
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func attach(to view: UIView) {
            self.view = view
            installRecognizerIfPossible()
            // The cell is not in the hierarchy yet on the first pass.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, self.view === view else { return }
                installRecognizerIfPossible()
            }
        }

        func detach() {
            if let recognizer, let gestureHostView {
                gestureHostView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            view = nil
            gestureHostView = nil
            hasPassedMinimumDistance = false
        }

        private func installRecognizerIfPossible() {
            guard let view, let hostView = gestureHost(for: view), gestureHostView !== hostView else { return }
            if let recognizer, let gestureHostView {
                gestureHostView.removeGestureRecognizer(recognizer)
            }
            let panRecognizer = recognizer ?? ThreadChatDirectionalPanRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            panRecognizer.targetKind = targetKind
            panRecognizer.direction = direction
            panRecognizer.cancelsTouchesInView = false
            panRecognizer.delaysTouchesBegan = false
            panRecognizer.delaysTouchesEnded = false
            panRecognizer.delegate = self
            hostView.addGestureRecognizer(panRecognizer)
            recognizer = panRecognizer
            gestureHostView = hostView
        }

        private func gestureHost(for view: UIView) -> UIView? {
            var ancestor = view.superview
            while let current = ancestor {
                if current is UITableViewCell { return current }
                ancestor = current.superview
            }
            return view.superview
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            let value = ThreadChatDragValue(recognizer: recognizer, in: view)
            switch recognizer.state {
            case .began:
                hasPassedMinimumDistance = false
                handleChangedIfReady(value)
            case .changed:
                handleChangedIfReady(value)
            case .ended:
                handleChangedIfReady(value)
                finish(value)
            case .possible:
                break
            default:
                finish(value)
            }
        }

        private func finish(_ value: ThreadChatDragValue) {
            if hasPassedMinimumDistance { onEnded(value) }
            hasPassedMinimumDistance = false
        }

        private func handleChangedIfReady(_ value: ThreadChatDragValue) {
            if !hasPassedMinimumDistance {
                guard ThreadChatPanGestureResolver.hasPassedMinimumDistance(
                    translation: value.translation,
                    minimumDistance: minimumDistance
                ) else { return }
                hasPassedMinimumDistance = true
            }
            onChanged(value)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer, let view else { return true }
            guard view.bounds.contains(recognizer.location(in: view)) else { return false }
            let velocity = recognizer.velocity(in: view.window ?? view)
            return ThreadChatPanGestureResolver.hasDirectionalHorizontalIntent(
                velocity: CGSize(width: velocity.x, height: velocity.y),
                direction: direction
            )
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !touch.threadChatStartsOnSlider
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension UITouch {
    /// A drag on a slider, such as a voice message's scrubber, only moves the slider,
    /// so no chat swipe takes it.
    var threadChatStartsOnSlider: Bool {
        var current = view
        while let view = current {
            if view is UISlider { return true }
            current = view.superview
        }
        return false
    }
}

extension ThreadChatDragValue {
    /// Measured in window coordinates, so a view that moves under the finger doesn't skew it.
    init(recognizer: UIPanGestureRecognizer, in view: UIView) {
        let coordinateView = view.window ?? view
        let translation = recognizer.translation(in: coordinateView)
        let velocity = recognizer.velocity(in: coordinateView)
        self.init(
            translation: CGSize(width: translation.x, height: translation.y),
            velocity: CGSize(width: velocity.x, height: velocity.y)
        )
    }
}
