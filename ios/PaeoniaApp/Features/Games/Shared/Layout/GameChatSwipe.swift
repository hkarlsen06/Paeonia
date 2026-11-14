import MapKit
import PencilKit
import RealityKit
import SwiftUI
import UIKit

extension View {
    /// Marks a part of a game screen whose own gesture uses vertical drags, such as a board
    /// that lines are drawn on. A swipe that starts there never opens the game's chat.
    /// Pass false while the gesture is off, such as on the partner's turn.
    func keepsVerticalDrags(_ keeps: Bool = true) -> some View {
        background { if keeps { GameDragRegion() } }
    }
}

private struct GameDragRegion: UIViewRepresentable {
    func makeUIView(context _: Context) -> GameDragRegionView {
        let view = GameDragRegionView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_: GameDragRegionView, context _: Context) {}
}

/// Covers the part of a screen that `keepsVerticalDrags` marks. The regions on screen are
/// listed here because SwiftUI gestures have no view a hit test could find.
final class GameDragRegionView: UIView {
    private static let onScreen = NSHashTable<GameDragRegionView>.weakObjects()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            Self.onScreen.remove(self)
        } else {
            Self.onScreen.add(self)
        }
    }

    /// A marked region holds `point`, in the window's coordinates.
    static func holds(_ point: CGPoint) -> Bool {
        onScreen.allObjects.contains { $0.convert($0.bounds, to: nil).contains(point) }
    }
}

/// Says whether a vertical swipe may open or close the game chat, or belongs to
/// something under the finger.
@MainActor
enum GameChatSwipeRules {
    /// Nothing at `point`, in the window's coordinates, wants a drag that moves the
    /// finger up or down: no drawing canvas, map, 3D scene or marked region, and no
    /// scroll view that can still scroll that way.
    static func isFree(at point: CGPoint, in window: UIWindow, fingerMovesUp: Bool, scrollsAlwaysWin: Bool) -> Bool {
        guard !GameDragRegionView.holds(point) else { return false }
        var view = window.hitTest(point, with: nil)
        while let current = view {
            // A map pans, and Ludo's die is carried and thrown with a drag on its scene.
            if current is MKMapView || current is ARView { return false }
            if let canvas = current as? PKCanvasView {
                if canvas.isUserInteractionEnabled { return false }
            } else if let scroll = current as? UIScrollView, scroll.isScrollEnabled {
                if scrollsAlwaysWin || canScroll(scroll, fingerMovesUp: fingerMovesUp) { return false }
            }
            view = current.superview
        }
        return true
    }

    /// A chat list is turned upside down, so the direction is taken from where the scroll
    /// view's own down points on screen.
    private static func canScroll(_ scroll: UIScrollView, fingerMovesUp: Bool) -> Bool {
        let inset = scroll.adjustedContentInset
        let first = -inset.top
        let last = scroll.contentSize.height + inset.bottom - scroll.bounds.height
        guard last - first > 1 else { return false }
        let isUpsideDown = scroll.convert(CGPoint(x: 0, y: 1), to: nil).y < scroll.convert(CGPoint.zero, to: nil).y
        let showsLaterContent = fingerMovesUp != isUpsideDown
        return showsLaterContent ? scroll.contentOffset.y < last - 1 : scroll.contentOffset.y > first + 1
    }

    /// The finger moves mostly up or mostly down.
    static func isVertical(_ velocity: CGPoint, up: Bool) -> Bool {
        abs(velocity.y) > abs(velocity.x) * 1.5 && (up ? velocity.y < 0 : velocity.y > 0)
    }
}

/// Opens the game's chat on a swipe up anywhere on a game screen that nothing else needs
/// the swipe for. It starts on a button as well as on empty space.
struct GameChatSwipeUp: UIViewRepresentable {
    let isEnabled: Bool
    let open: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.open = open
        context.coordinator.isEnabled = isEnabled
        // The screen's own view is found once this view is in a window.
        DispatchQueue.main.async {
            context.coordinator.install(from: uiView)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// How far up the finger goes before the chat opens.
        private static let distance: CGFloat = 40
        /// A swipe that ends this fast, in points a second, opens the chat whatever its length.
        private static let flickSpeed: CGFloat = 300

        var open: () -> Void = {}
        var isEnabled = false {
            didSet { recognizer?.isEnabled = isEnabled }
        }
        private var recognizer: UIPanGestureRecognizer?
        private var didOpen = false

        func install(from view: UIView) {
            guard recognizer == nil, let screen = view.gameScreenView() else { return }
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.delegate = self
            recognizer.isEnabled = isEnabled
            screen.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        func remove() {
            guard let recognizer else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            self.recognizer = nil
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                didOpen = false
            case .changed, .ended:
                // A quick flick can end before it has gone the distance.
                let moved = recognizer.translation(in: recognizer.view).y
                let speed = recognizer.velocity(in: recognizer.view).y
                let isFlick = recognizer.state == .ended && speed < -Self.flickSpeed
                guard !didOpen, moved <= -Self.distance || isFlick else { return }
                didOpen = true
                open()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view,
                let window = view.window, GameChatSwipeRules.isVertical(pan.velocity(in: view), up: true)
            else { return false }
            return GameChatSwipeRules.isFree(
                at: pan.location(in: nil), in: window, fingerMovesUp: true, scrollsAlwaysWin: false)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Drags the game chat panel down from anywhere on it that nothing else needs the drag
/// for, and from the small game above it. The messages scroll first. While the keyboard
/// is up, a drag on them takes the keyboard away instead, as it does in every chat.
struct GameChatPanelDrag: UIViewRepresentable {
    /// How far down the panel has been dragged.
    let onChanged: (CGFloat) -> Void
    /// The finger left. True when the drag went far or fast enough to close the panel.
    let onEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        // The window is there once this view is in it.
        DispatchQueue.main.async {
            context.coordinator.install(on: uiView)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// A drag this far, counting where its speed would carry it, closes the panel.
        private static let closeDistance: CGFloat = 120

        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (Bool) -> Void = { _ in }
        /// Its frame is the panel's.
        private weak var panel: UIView?
        private var recognizer: UIPanGestureRecognizer?
        private var isKeyboardUp = false
        /// The touch began above the panel, on the small game.
        private var startedOnGame = false
        private var keyboardObservers: [NSObjectProtocol] = []

        /// The recognizer sits on the window, because the panel is SwiftUI with a
        /// navigation stack inside and has no one view of its own.
        func install(on panel: UIView) {
            guard recognizer == nil, let window = panel.window else { return }
            self.panel = panel
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.isKeyboardUp = true }
                },
                center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.isKeyboardUp = false }
                },
            ]
        }

        func remove() {
            keyboardObservers.forEach(NotificationCenter.default.removeObserver)
            keyboardObservers = []
            guard let recognizer else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            self.recognizer = nil
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let moved = recognizer.translation(in: nil).y
            switch recognizer.state {
            case .began, .changed:
                onChanged(max(0, moved))
            case .ended:
                onEnded(moved + recognizer.velocity(in: nil).y * 0.15 > Self.closeDistance)
            case .cancelled, .failed:
                onEnded(false)
            default:
                break
            }
        }

        /// On the panel, and on the game above it, where a drag down pulls the panel along.
        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let panel, panel.window != nil else { return false }
            let frame = panel.convert(panel.bounds, to: nil)
            let point = touch.location(in: nil)
            startedOnGame = point.y < frame.minY
            return startedOnGame || frame.contains(point)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let window = pan.view as? UIWindow,
                GameChatSwipeRules.isVertical(pan.velocity(in: nil), up: false)
            else { return false }
            // The game takes no touches while the panel is open, so nothing there wants the drag.
            if startedOnGame { return true }
            return GameChatSwipeRules.isFree(
                at: pan.location(in: nil), in: window, fingerMovesUp: false, scrollsAlwaysWin: isKeyboardUp)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    /// The view of the screen this view is in.
    func gameScreenView() -> UIView? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller.view }
            responder = current.next
        }
        return nil
    }
}
