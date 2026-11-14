import MapKit
import MapLibre
import PencilKit
import RealityKit
import SwiftUI
import UIKit

extension View {
    /// Lets a swipe in from the right edge of the screen pull the couple chat ("Just us")
    /// over this view, on any tab. The chat follows the finger, and lets go open past a
    /// third of the screen or on a flick. Its back button and a swipe right slide it away
    /// again, back to the screen it covered. `isPresented` is true while it is open.
    func coupleChatSlideOver(isPresented: Binding<Bool>, isEnabled: Bool) -> some View {
        modifier(CoupleChatSlideOver(isPresented: isPresented, isEnabled: isEnabled))
    }
}

/// Where the couple chat is between the right edge and covering the screen.
private enum CoupleChatSlidePosition: Equatable {
    case hidden
    /// Following a finger that has come this far in from the edge.
    case dragging(CGFloat)
    case shown
}

private struct CoupleChatSlideOver: ViewModifier {
    /// Past this share of the screen, counting where the finger's speed would carry it,
    /// the chat stays open when the finger lets go.
    private static let openFraction: CGFloat = 1 / 3

    @Binding var isPresented: Bool
    let isEnabled: Bool

    @Environment(\.threadChatContext) private var chatContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = CoupleChatSlidePosition.hidden
    /// On screen from the start of the swipe until the chat has slid away again.
    @State private var isMounted = false
    /// Read once and kept, so the next swipe shows the chat from its first frame.
    @State private var chat: ThreadChatViewModel?
    @State private var width: CGFloat = 0

    private var slide: Animation? {
        reduceMotion ? nil : .spring(duration: PaeoniaMotion.motionDefault, bounce: 0)
    }

    private var isDragging: Bool {
        if case .dragging = position { return true }
        return false
    }

    private var offset: CGFloat {
        switch position {
        case .hidden: width
        case .dragging(let distance): max(0, width - distance)
        case .shown: 0
        }
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(position == .shown)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background {
                // Off while the chat is open, so its own swipes near the edge work, but on
                // for the whole of a swipe, which shows the chat and so ends the screen's
                // `isEnabled`.
                RightEdgeSwipe(
                    isEnabled: isDragging || (isEnabled && chatContext.isAvailable && !isMounted),
                    onBegan: begin,
                    onChanged: { position = .dragging($0) },
                    onEnded: end(projectedDistance:)
                )
            }
            .overlay { if isMounted { slideOver } }
            .onChange(of: chatContext.coupleID) { _, _ in
                chat = nil
                hide()
            }
            .onChange(of: isPresented) { _, isPresented in
                if !isPresented, position == .shown { hide() }
            }
    }

    private var slideOver: some View {
        let progress = width > 0 ? 1 - offset / width : 0
        return ZStack {
            Color.black.opacity(0.3 * progress)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Group {
                if let chat {
                    ThreadChatScreen(viewModel: chat, presentation: .slideOver, onClose: hide)
                } else {
                    Color.paeoniaBackgroundPrimary.ignoresSafeArea()
                }
            }
            .shadow(color: .black.opacity(0.25 * progress), radius: 16)
            .modifier(PanelSlide(offset: offset, axis: .horizontal))
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, hide)
        }
    }

    private func begin() {
        PaeoniaKeyboard.dismiss()
        isMounted = true
        position = .dragging(0)
        guard chat == nil, let coupleID = chatContext.coupleID else { return }
        Task {
            let model = await chatContext.makeViewModel(subject: .couple, header: nil)
            // Another couple's chat never shows, even when the couple changed while it was read.
            guard chat == nil, chatContext.coupleID == coupleID else { return }
            chat = model
        }
    }

    private func end(projectedDistance: CGFloat) {
        guard projectedDistance > width * Self.openFraction else {
            hide()
            return
        }
        withAnimation(slide) { position = .shown }
        isPresented = true
        AccessibilityNotification.ScreenChanged().post()
    }

    private func hide() {
        guard isMounted else { return }
        let wasShown = position == .shown
        PaeoniaKeyboard.dismiss()
        isPresented = false
        withAnimation(slide) {
            position = .hidden
        } completion: {
            guard position == .hidden else { return }
            isMounted = false
            if wasShown { AccessibilityNotification.ScreenChanged().post() }
        }
    }
}

/// A swipe that starts at the right edge of the screen and moves in. It sits on the window,
/// because the tabs are UIKit containers with SwiftUI inside, and takes only touches on the
/// screens under this view, never on a sheet over them. At the edge it wins over the
/// scrolling, dragging and buttons under the finger, as the system's back swipe does at
/// the left edge.
private struct RightEdgeSwipe: UIViewRepresentable {
    let isEnabled: Bool
    let onBegan: () -> Void
    /// How far in from the edge the finger has come.
    let onChanged: (CGFloat) -> Void
    /// The finger left. Says how far in it was, counting where its speed would carry it.
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.isEnabled = isEnabled
        // The window is there once this view is in it.
        DispatchQueue.main.async {
            context.coordinator.install(from: uiView)
        }
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// A touch this close to the right edge can start the swipe. The finger lands
        /// about this far in when it comes in from the side of the phone.
        private static let edgeWidth: CGFloat = 24

        var onBegan: () -> Void = {}
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        var isEnabled = false {
            didSet { recognizer?.isEnabled = isEnabled }
        }
        /// The screens this swipe works on. A sheet or cover is outside it.
        private weak var screens: UIView?
        private var recognizer: UIPanGestureRecognizer?

        func install(from view: UIView) {
            guard recognizer == nil, let window = view.window else { return }
            screens = window.rootViewController?.view
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            recognizer.isEnabled = isEnabled
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        func remove() {
            guard let recognizer else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            self.recognizer = nil
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let distance = -recognizer.translation(in: nil).x
            switch recognizer.state {
            case .began:
                onBegan()
                onChanged(max(0, distance))
            case .changed:
                onChanged(max(0, distance))
            case .ended:
                onEnded(distance - recognizer.velocity(in: nil).x * 0.15)
            case .cancelled, .failed:
                onEnded(0)
            default:
                break
            }
        }

        /// Only a finger at the right edge of the tabs. A drawing, a map, a game's 3D scene or
        /// board, and a slider keep a drag that starts on them, even there.
        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let point = touch.location(in: nil)
            guard touch.type == .direct, let screens, let window = screens.window, let view = touch.view,
                view.isDescendant(of: screens), point.x >= window.bounds.maxX - Self.edgeWidth,
                !GameDragRegionView.holds(point)
            else { return false }
            return !touch.startsInView { view in
                (view is PKCanvasView && view.isUserInteractionEnabled) || view is MKMapView || view is MLNMapView
                    || view is ARView || view is UISlider
            }
        }

        /// The finger moves mostly left. A drag up or down at the edge still scrolls.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: nil)
            return ThreadChatPanGestureResolver.hasDirectionalHorizontalIntent(
                velocity: CGSize(width: velocity.x, height: velocity.y),
                direction: .left
            )
        }

        /// A pan under the finger waits until this swipe has failed. Only a touch at the
        /// edge reaches this swipe, so nothing else waits.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer !== gestureRecognizer
        }
    }
}
