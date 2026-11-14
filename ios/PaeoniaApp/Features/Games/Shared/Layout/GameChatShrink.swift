import SwiftUI
import UIKit

/// How small the Games tab shows while a game's chat panel is open, and where.
nonisolated struct GameChatShrink: Equatable, Sendable {
    /// The screen's size as a share of its full size.
    let scale: CGFloat
    /// Where the shrunk screen's top left corner goes, in global coordinates.
    let origin: CGPoint
    /// The first row of the screen that shows, in global coordinates at full size. What is
    /// above it is cut off. 0 shows the screen from its top.
    let top: CGFloat
}

extension EnvironmentValues {
    /// Set while the game chat panel is open (`GameChatPanel`).
    @Entry var gameChatShrink: GameChatShrink?
}

/// A game screen's navigation bar shows something about the game, such as the score, and
/// not only the buttons every game has.
struct GameToolbarInfoKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Where a game screen's content starts under its navigation bar, in global coordinates,
/// when the bar holds nothing about the game. The chat panel then leaves the bar out of
/// the small screen. Nil keeps the bar.
struct GameChatContentTopKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Says a game screen's navigation bar shows something about the game, so the bar stays
    /// in view above the game's chat panel.
    func gameToolbarShowsInfo(_ shows: Bool = true) -> some View {
        preference(key: GameToolbarInfoKey.self, value: shows)
    }

    /// Makes a screen of the Games tab shrink above its game's chat panel, and open that
    /// chat on a swipe up. `kind` is the game the screen belongs to.
    func gameChatScreen(kind: GameKind) -> some View {
        modifier(GameChatScreen(kind: kind))
    }
}

/// A screen of the Games tab while a game's chat panel is open. The whole screen, with its
/// navigation bar, shows smaller above the panel and keeps running, the way a video stays
/// in view over its comments. The game's layout stays as it is: the chat's keyboard is not
/// the game's, so the screen does not make room for it.
struct GameChatScreen: ViewModifier {
    let kind: GameKind

    @Environment(\.gameChatShrink) private var shrink
    @Environment(\.threadChatContext) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The keyboard on screen is the chat's. It stays so until it is gone, which is
    /// after the panel has closed.
    @State private var chatHasKeyboard = false
    @State private var toolbarShowsInfo = false
    /// The screen's top edge under the navigation bar, in global coordinates at full size.
    @State private var contentTop: CGFloat?

    func body(content: Content) -> some View {
        let keyboardIsChats = shrink != nil || chatHasKeyboard
        content
            .onPreferenceChange(GameToolbarInfoKey.self) { toolbarShowsInfo = $0 }
            // Only at full size. The shrink also scales what a screen reports.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                if shrink == nil { contentTop = top }
            }
            .preference(key: GameChatContentTopKey.self, value: toolbarShowsInfo ? nil : contentTop)
            .environment(\.keyboardBelongsElsewhere, keyboardIsChats)
            .background { GameScreenShrinker(shrink: shrink, animates: !reduceMotion) }
            .background {
                GameChatSwipeUp(isEnabled: shrink == nil && chat.isAvailable && chat.openGameChat != nil) {
                    chat.openGameChat?(kind, nil, nil)
                }
            }
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
            let mask = stack.layer.mask as? CAShapeLayer ?? Self.addMask(to: stack)
            let shownPath = mask.presentation()?.path ?? mask.path
            let top = shrink.map { stack.convert(CGPoint(x: 0, y: $0.top), from: nil).y }
            let path = Self.maskPath(for: stack, top: top)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak stack, weak layer] in
                // Back at full size, where the mask would only cut the corners of the screen.
                guard let stack, let layer, CATransform3DIsIdentity(layer.sublayerTransform) else { return }
                stack.layer.mask = nil
            }
            layer.sublayerTransform = transform
            mask.path = path
            if animates {
                layer.add(Self.animation("sublayerTransform", from: shown, to: transform), forKey: Self.animationKey)
                mask.add(Self.animation("path", from: shownPath, to: path), forKey: Self.animationKey)
            } else {
                layer.removeAnimation(forKey: Self.animationKey)
                mask.removeAnimation(forKey: Self.animationKey)
            }
            CATransaction.commit()
        }

        func restore() {
            guard let stack else { return }
            stack.superview?.layer.removeAnimation(forKey: Self.animationKey)
            stack.superview?.layer.sublayerTransform = CATransform3DIdentity
            stack.layer.mask = nil
        }

        private static func animation(_ keyPath: String, from: Any?, to: Any?) -> CAAnimation {
            let animation = CASpringAnimation(perceptualDuration: PaeoniaMotion.motionDefault, bounce: 0)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            return animation
        }

        /// The mask gives the small screen round corners, like the phone's own, and cuts
        /// off what is above its first row.
        private static func addMask(to stack: UIView) -> CAShapeLayer {
            let mask = CAShapeLayer()
            mask.frame = stack.bounds
            mask.path = maskPath(for: stack, top: nil)
            stack.layer.mask = mask
            return mask
        }

        private static func maskPath(for stack: UIView, top: CGFloat?) -> CGPath {
            var rect = stack.bounds
            if let top {
                rect.size.height -= top - rect.minY
                rect.origin.y = top
            }
            return UIBezierPath(roundedRect: rect, cornerRadius: top == nil ? 0.1 : cornerRadius).cgPath
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
