import SwiftUI
import UIKit

/// How small the Games tab shows while a game's chat panel is open, and where.
nonisolated struct GameChatShrink: Equatable, Sendable {
    /// The screen's size as a share of its full size.
    let scale: CGFloat
    /// Where the shrunk screen's top left corner goes, in global coordinates.
    let origin: CGPoint
}

extension EnvironmentValues {
    /// Set while the game chat panel is open (`GameChatPanel`).
    @Entry var gameChatShrink: GameChatShrink?
}

extension View {
    /// Makes a screen of the Games tab shrink above its game's chat panel.
    func gameChatScreen() -> some View {
        modifier(GameChatScreen())
    }
}

/// A screen of the Games tab while a game's chat panel is open. The whole screen, with its
/// navigation bar, shows smaller above the panel and keeps running, the way a video stays
/// in view over its comments. The game's layout stays as it is: the chat's keyboard is not
/// the game's, so the screen does not make room for it.
struct GameChatScreen: ViewModifier {
    @Environment(\.gameChatShrink) private var shrink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The keyboard on screen is the chat's. It stays so until it is gone, which is
    /// after the panel has closed.
    @State private var chatHasKeyboard = false

    func body(content: Content) -> some View {
        let keyboardIsChats = shrink != nil || chatHasKeyboard
        content
            .environment(\.keyboardBelongsElsewhere, keyboardIsChats)
            .background { GameScreenShrinker(shrink: shrink, animates: !reduceMotion) }
            // The chat's keyboard would squeeze the game above the panel, and again on its way out.
            .ignoresSafeArea(.keyboard, edges: keyboardIsChats ? .bottom : [])
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if shrink != nil { chatHasKeyboard = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                chatHasKeyboard = false
            }
    }
}

/// Shrinks the navigation stack a game screen is in, on its layer.
///
/// The stack's view keeps its frame, and only the layer above it draws it smaller
/// (`sublayerTransform`). A transform on the view itself, which is what `scaleEffect` around
/// the stack sets, moves the view's frame, and UIKit then gives the screen a different safe
/// area and the game lays itself out again.
private struct GameScreenShrinker: UIViewRepresentable {
    let shrink: GameChatShrink?
    let animates: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let shrink = shrink
        let animates = animates
        // The navigation controller is found once the view is in a window.
        DispatchQueue.main.async {
            context.coordinator.apply(shrink, from: uiView, animates: animates)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.restore()
    }

    @MainActor
    final class Coordinator {
        /// The corners of the small screen, at full size.
        private static let cornerRadius: CGFloat = 44
        private static let animationKey = "gameChatShrink"
        private weak var stack: UIView?

        func apply(_ shrink: GameChatShrink?, from view: UIView, animates: Bool) {
            // A screen under another one is out of the window and leaves the stack to that one.
            guard view.window != nil, let stack = stack ?? view.gameNavigationController()?.view,
                let host = stack.superview
            else { return }
            self.stack = stack
            let transform = shrink.map { Self.transform($0, in: host) } ?? CATransform3DIdentity
            let layer = host.layer
            guard !CATransform3DEqualToTransform(layer.sublayerTransform, transform) else { return }
            let shown = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
            if shrink != nil { setsCorners(true, on: stack) }
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self, weak stack, weak layer] in
                guard let stack, let layer, CATransform3DIsIdentity(layer.sublayerTransform) else { return }
                self?.setsCorners(false, on: stack)
            }
            layer.sublayerTransform = transform
            if animates {
                let animation = CASpringAnimation(perceptualDuration: PaeoniaMotion.motionMorph, bounce: 0)
                animation.keyPath = "sublayerTransform"
                animation.fromValue = shown
                animation.toValue = transform
                layer.add(animation, forKey: Self.animationKey)
            } else {
                layer.removeAnimation(forKey: Self.animationKey)
            }
            CATransaction.commit()
        }

        func restore() {
            guard let stack else { return }
            stack.superview?.layer.removeAnimation(forKey: Self.animationKey)
            stack.superview?.layer.sublayerTransform = CATransform3DIdentity
            setsCorners(false, on: stack)
        }

        /// The small screen has round corners, like the phone's own. At full size they
        /// would cut into the screen on a phone with square corners.
        private func setsCorners(_ rounds: Bool, on stack: UIView) {
            stack.layer.cornerRadius = rounds ? Self.cornerRadius : 0
            stack.layer.cornerCurve = .continuous
            stack.layer.masksToBounds = rounds
        }

        /// A sublayer transform works around its layer's anchor point, so the move makes
        /// up for the shrink towards that point.
        private static func transform(_ shrink: GameChatShrink, in host: UIView) -> CATransform3D {
            let origin = host.convert(shrink.origin, from: nil)
            let anchor = CGPoint(
                x: host.bounds.minX + host.bounds.width * host.layer.anchorPoint.x,
                y: host.bounds.minY + host.bounds.height * host.layer.anchorPoint.y
            )
            return CATransform3DMakeAffineTransform(
                CGAffineTransform(
                    a: shrink.scale, b: 0, c: 0, d: shrink.scale,
                    tx: origin.x - anchor.x * (1 - shrink.scale),
                    ty: origin.y - anchor.y * (1 - shrink.scale)
                )
            )
        }
    }
}
