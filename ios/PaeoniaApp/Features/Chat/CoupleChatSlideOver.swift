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
    ///
    /// While `peeks` is true the chat's edge peeks in from the right a moment and goes back,
    /// the way the swipe pulls it, as `SwipeLessons` allows.
    func coupleChatSlideOver(isPresented: Binding<Bool>, isEnabled: Bool, peeks: Bool) -> some View {
        modifier(CoupleChatSlideOver(isPresented: isPresented, isEnabled: isEnabled, peeks: peeks))
    }
}

/// Where the couple chat is between the right edge and covering the screen.
private enum CoupleChatSlidePosition: Equatable {
    case hidden
    /// Just its edge, for a moment, so the person finds the swipe.
    case peeking
    /// Following a finger that has come this far in from the edge.
    case dragging(CGFloat)
    case shown
}

private struct CoupleChatSlideOver: ViewModifier {
    /// Past this share of the screen, counting where the finger's speed would carry it,
    /// the chat stays open when the finger lets go.
    private static let openFraction: CGFloat = 1 / 3
    /// How much of the chat shows while it peeks in.
    private static let peekWidth: CGFloat = 64

    @Binding var isPresented: Bool
    let isEnabled: Bool
    let peeks: Bool

    @Environment(\.threadChatContext) private var chatContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = CoupleChatSlidePosition.hidden
    /// On screen from the start of the swipe until the chat has slid away again.
    @State private var isMounted = false
    /// Read once and kept, so the next swipe shows the chat from its first frame.
    @State private var chat: ThreadChatViewModel?
    @State private var width: CGFloat = 0
    /// The peek's strip is on screen instead of the chat, from the peek until it has gone
    /// back or a swipe has taken it over. The peek never reads the chat, so it marks nothing read.
    @State private var showsPeek = false
    /// The keyboard on screen is the chat's. It stays so until it is gone, which can be
    /// after the chat has slid away.
    @State private var chatHasKeyboard = false

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
        case .peeking: width - Self.peekWidth
        case .dragging(let distance): max(0, width - distance)
        case .shown: 0
        }
    }

    func body(content: Content) -> some View {
        // The screens under the chat keep their layout while its keyboard is up, so a game
        // or a drawing is not squeezed, and drawn again smaller, out of sight.
        let keyboardIsChats = (isMounted && !showsPeek) || chatHasKeyboard
        content
            .environment(\.keyboardBelongsElsewhere, keyboardIsChats)
            .ignoresSafeArea(.keyboard, edges: keyboardIsChats ? .bottom : [])
            .accessibilityHidden(position == .shown)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background {
                // Off while the chat is open, so its own swipes near the edge work, but on
                // for the whole of a swipe, which shows the chat and so ends the screen's
                // `isEnabled`.
                RightEdgeSwipe(
                    isEnabled: isDragging || position == .peeking
                        || (isEnabled && chatContext.isAvailable && !isMounted),
                    onBegan: begin,
                    onChanged: { position = .dragging($0) },
                    onEnded: end(projectedDistance:)
                )
            }
            .overlay { if isMounted { slideOver } }
            .task(id: peeks && isEnabled && chatContext.isAvailable) { await peek() }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if isMounted, !showsPeek { chatHasKeyboard = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                chatHasKeyboard = false
            }
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
            if showsPeek {
                CoupleChatPeekStrip(participants: chatContext.participants, width: Self.peekWidth)
                    .shadow(color: .black.opacity(0.3), radius: 16)
                    .modifier(PanelSlide(offset: offset, axis: .horizontal))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
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
    }

    /// A moment after a screen that welcomes it settles, the chat's edge peeks in and goes
    /// back. The screen changing, or a sheet over it, ends the peek early. A swipe that
    /// starts during the peek takes the chat from where it is.
    private func peek() async {
        guard peeks, isEnabled, chatContext.isAvailable, !reduceMotion, !isMounted,
              SwipeLessons[.justUs].peekIsDue(at: .now, calendar: .current)
        else { return }
        do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
        guard !isMounted, !GameChatSwipeRules.appIsCovered() else { return }
        SwipeLessons[.justUs].peeked(at: .now)
        showsPeek = true
        isMounted = true
        // Built at the edge first, then slid in once it is on screen.
        try? await Task.sleep(for: .milliseconds(50))
        if position == .hidden, !Task.isCancelled {
            withAnimation(slide) { position = .peeking }
            try? await Task.sleep(for: .seconds(1.4))
        }
        guard position == .peeking || position == .hidden, showsPeek else { return }
        withAnimation(slide) {
            position = .hidden
        } completion: {
            guard position == .hidden else { return }
            isMounted = false
            showsPeek = false
        }
    }

    private func begin() {
        PaeoniaKeyboard.dismiss()
        showsPeek = false
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
        SwipeLessons[.justUs].swiped()
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

/// The chat's left edge while it peeks in: the partner's face on the chat's background, so it
/// reads as the chat the swipe opens.
private struct CoupleChatPeekStrip: View {
    let participants: DailyChallengeParticipants
    /// How much of the strip shows.
    let width: CGFloat

    var body: some View {
        Color.paeoniaBackgroundPrimary
            .clipShape(.rect(topLeadingRadius: PaeoniaRadius.radius28, bottomLeadingRadius: PaeoniaRadius.radius28))
            .overlay(alignment: .leading) {
                PaeoniaCoupleAvatar(
                    mediaAssetID: participants.partnerProfilePhotoAssetID,
                    name: participants.partnerName,
                    tint: .paeoniaPartnerTwo,
                    size: 40,
                    isCurrentUser: false
                )
                .frame(width: width)
            }
            .ignoresSafeArea()
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
