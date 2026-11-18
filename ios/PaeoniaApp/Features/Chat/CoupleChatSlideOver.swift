import MapKit
import MapLibre
import PencilKit
import RealityKit
import SwiftUI
import UIKit

extension View {
    /// Lets a swipe in from the right edge of the screen pull the couple chat ("Just us")
    /// over this view, on any tab. The chat follows the finger, and lets go open past a
    /// third of the screen or on a flick. A finger at the chat's left edge drags it away the
    /// same way, back to the screen it covered, and its back button and a swipe right on the
    /// messages slide it away too. `isPresented` is true while it is open, and setting it
    /// slides the chat in, such as from Message on the partner's avatar.
    ///
    /// While `peeks` is true the chat's edge peeks in from the right a moment and goes back,
    /// the way the swipe pulls it, as `SwipeLessons` allows. It peeks too each time
    /// `partnerOpened` grows while `partnerPeeks` is true, however well the person knows the
    /// swipe, because the partner is in the chat now. A tap on the edge while it shows slides
    /// the chat in, and a swipe that starts on it pulls the chat from there.
    func coupleChatSlideOver(
        isPresented: Binding<Bool>, isEnabled: Bool, peeks: Bool, partnerOpened: Int, partnerPeeks: Bool
    ) -> some View {
        modifier(
            CoupleChatSlideOver(
                isPresented: isPresented, isEnabled: isEnabled, peeks: peeks, partnerOpened: partnerOpened,
                partnerPeeks: partnerPeeks
            )
        )
    }
}

/// Where the couple chat is between the right edge and covering the screen.
private enum CoupleChatSlidePosition: Equatable {
    case hidden
    /// Just its edge, for a moment, so the person finds the swipe or sees the partner is in it.
    case peeking
    /// Following a finger, with the chat this far in from the right edge. The finger came in
    /// from the screen's right edge to open it, or from the chat's left edge to close it.
    case dragging(CGFloat, from: EdgeSwipe.Edge)
    case shown
}

private struct CoupleChatSlideOver: ViewModifier {
    /// Past this share of the screen, counting where the finger's speed would carry it, the
    /// chat ends up where the finger was taking it when the finger lets go.
    private static let settleFraction: CGFloat = 1 / 3
    /// How much of the chat shows while it peeks in.
    private static let peekWidth: CGFloat = 64

    @Binding var isPresented: Bool
    let isEnabled: Bool
    let peeks: Bool
    let partnerOpened: Int
    let partnerPeeks: Bool

    @Environment(\.threadChatContext) private var chatContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var position = CoupleChatSlidePosition.hidden
    /// On screen from the start of the swipe until the chat has slid away again.
    @State private var isMounted = false
    /// Read once and kept, so the next swipe shows the chat from its first frame.
    @State private var chat: ThreadChatViewModel?
    @State private var width: CGFloat = 0
    /// How far in the chat was when the swipe began, which is the peek's width during a peek.
    @State private var swipeStart: CGFloat = 0
    /// The peek's strip is on screen instead of the chat, from the peek until it has gone
    /// back or a swipe has taken it over. The peek never reads the chat, so it marks nothing read.
    @State private var showsPeek = false
    /// The keyboard on screen is the chat's. It stays so until it is gone, which can be
    /// after the chat has slid away.
    @State private var chatHasKeyboard = false
    /// The peek for the partner opening the chat, which the screen changing ends early.
    @State private var partnerPeek: Task<Void, Never>?

    private var slide: Animation? {
        reduceMotion ? nil : .spring(duration: PaeoniaMotion.motionDefault, bounce: 0)
    }

    private var draggingEdge: EdgeSwipe.Edge? {
        if case .dragging(_, let edge) = position { return edge }
        return nil
    }

    /// The chat is open, or a finger is taking it away.
    private var isOpen: Bool {
        position == .shown || draggingEdge == .left
    }

    private var offset: CGFloat {
        switch position {
        case .hidden: width
        case .peeking: width - Self.peekWidth
        case .dragging(let distance, _): max(0, width - distance)
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
            .background { edgeSwipes }
            .overlay { if isMounted { slideOver } }
            .task(id: peeks && isEnabled && chatContext.isAvailable) { await peek(teaches: true) }
            .onChange(of: partnerOpened) { _, _ in
                partnerPeek?.cancel()
                guard partnerPeeks, isEnabled else { return }
                partnerPeek = Task { await peek(teaches: false) }
            }
            .onChange(of: partnerPeeks && isEnabled) { _, welcome in
                if !welcome { partnerPeek?.cancel() }
            }
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
                if isPresented, position != .shown {
                    slideIn()
                } else if !isPresented, isOpen {
                    hide()
                }
            }
    }

    private var edgeSwipes: some View {
        ZStack {
            // Off while the chat is open, so its own swipes near the edge work, but on for the
            // whole of a swipe, which shows the chat and so ends the screen's `isEnabled`.
            EdgeSwipe(
                edge: .right,
                isEnabled: draggingEdge == .right || showsPeek
                    || (isEnabled && chatContext.isAvailable && !isMounted),
                reach: showsPeek ? Self.peekWidth : EdgeSwipe.edgeWidth,
                onBegan: begin,
                onChanged: { position = .dragging(swipeStart + $0, from: .right) },
                onEnded: { end(projectedDistance: swipeStart + $0) }
            )
            // Like the system's back swipe, which a chat at the root of its stack doesn't have.
            EdgeSwipe(
                edge: .left,
                isEnabled: isOpen,
                onBegan: { position = .dragging(width, from: .left) },
                onChanged: { position = .dragging(width - $0, from: .left) },
                onEnded: endClosing(projectedDistance:)
            )
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
                    .onTapGesture { isPresented = true }
                    .shadow(color: .black.opacity(0.3), radius: 16)
                    .modifier(PanelSlide(offset: offset, axis: .horizontal))
                    .accessibilityHidden(true)
            } else {
                Group {
                    if let chat {
                        ThreadChatScreen(viewModel: chat, presentation: .slideOver, onClose: close)
                    } else {
                        Color.paeoniaBackgroundPrimary.ignoresSafeArea()
                    }
                }
                .shadow(color: .black.opacity(0.25 * progress), radius: 16)
                .modifier(PanelSlide(offset: offset, axis: .horizontal))
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, close)
            }
        }
    }

    /// A moment after a screen that welcomes it settles, or the partner opens the chat, the
    /// chat's edge peeks in and goes back. A peek that `teaches` the swipe is one of the few
    /// `SwipeLessons` allows. The screen changing, or a sheet over it, ends the peek early. A
    /// tap or a swipe during the peek takes the chat from where it is.
    private func peek(teaches: Bool) async {
        guard isEnabled, chatContext.isAvailable, !reduceMotion, !isMounted,
              !teaches || (peeks && SwipeLessons[.justUs].peekIsDue(at: .now, calendar: .current))
        else { return }
        do { try await Task.sleep(for: teaches ? .seconds(1.6) : .milliseconds(300)) } catch { return }
        guard !isMounted, !PaeoniaAppWindow.isCovered else { return }
        if teaches { SwipeLessons[.justUs].peeked(at: .now) }
        showsPeek = true
        isMounted = true
        await Self.waitUntilMounted()
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
        swipeStart = position == .peeking ? Self.peekWidth : 0
        showsPeek = false
        isMounted = true
        position = .dragging(swipeStart, from: .right)
        guard chat == nil, let coupleID = chatContext.coupleID else { return }
        Task {
            let model = await chatContext.makeViewModel(subject: .couple, header: nil)
            // Another couple's chat never shows, even when the couple changed while it was read.
            guard chat == nil, chatContext.coupleID == coupleID else { return }
            chat = model
        }
    }

    /// Opens the chat without a swipe.
    private func slideIn() {
        guard chatContext.isAvailable else {
            isPresented = false
            return
        }
        begin()
        Task {
            await Self.waitUntilMounted()
            guard isPresented, isMounted else { return }
            withAnimation(slide) { position = .shown }
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    /// The chat is built at the edge first, and slides in once it is on screen.
    private static func waitUntilMounted() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func end(projectedDistance: CGFloat) {
        guard projectedDistance > width * Self.settleFraction else {
            hide()
            return
        }
        SwipeLessons[.justUs].swiped()
        withAnimation(slide) { position = .shown }
        isPresented = true
        AccessibilityNotification.ScreenChanged().post()
    }

    private func endClosing(projectedDistance: CGFloat) {
        if projectedDistance > width * Self.settleFraction {
            close()
        } else {
            withAnimation(slide) { position = .shown }
        }
    }

    /// The person closed the chat. Someone who keeps opening it with a tap gets one tip about the
    /// swipe once it has slid away, over the screen it covered, where the swipe works.
    private func close() {
        hide {
            guard SwipeLessons[.justUs].takeTip() else { return }
            bannerCenter.show(.info(message: String(localized: .chatsCoupleChatSwipeTip), systemImage: "hand.draw"))
        }
    }

    private func hide(then done: @escaping () -> Void = {}) {
        guard isMounted else { return }
        let wasShown = isOpen
        PaeoniaKeyboard.dismiss()
        isPresented = false
        withAnimation(slide) {
            position = .hidden
        } completion: {
            guard position == .hidden else { return }
            isMounted = false
            if wasShown { AccessibilityNotification.ScreenChanged().post() }
            done()
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

/// A swipe that starts at one edge of the screen and moves away from it. It sits on the window,
/// because the tabs are UIKit containers with SwiftUI inside, and takes only touches on the
/// screens under this view, never on a sheet over them. At the edge it wins over the
/// scrolling, dragging and buttons under the finger, as the system's back swipe does.
private struct EdgeSwipe: UIViewRepresentable {
    enum Edge {
        /// Opens the chat over the screens.
        case right
        /// Closes the chat that covers them.
        case left
    }

    /// A touch this close to the edge can start the swipe. The finger lands about this far in
    /// when it comes in from the side of the phone.
    static let edgeWidth: CGFloat = 24

    let edge: Edge
    let isEnabled: Bool
    /// How far from the edge a touch can start the swipe.
    var reach = edgeWidth
    let onBegan: () -> Void
    /// How far from the edge the finger has come.
    let onChanged: (CGFloat) -> Void
    /// The finger left. Says how far from the edge it was, counting where its speed would carry it.
    let onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(edge: edge)
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
        context.coordinator.reach = reach
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
        let edge: Edge
        var reach = EdgeSwipe.edgeWidth
        var onBegan: () -> Void = {}
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        var isEnabled = false {
            didSet { recognizer?.isEnabled = isEnabled }
        }
        /// The screens this swipe works on. A sheet or cover is outside it.
        private weak var screens: UIView?
        private var recognizer: UIPanGestureRecognizer?

        /// Moving away from the right edge is moving left.
        private var away: CGFloat { edge == .right ? -1 : 1 }

        init(edge: Edge) {
            self.edge = edge
        }

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
            let distance = away * recognizer.translation(in: nil).x
            switch recognizer.state {
            case .began:
                onBegan()
                onChanged(max(0, distance))
            case .changed:
                onChanged(max(0, distance))
            case .ended:
                onEnded(distance + away * recognizer.velocity(in: nil).x * 0.15)
            case .cancelled, .failed:
                onEnded(0)
            default:
                break
            }
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let point = touch.location(in: nil)
            guard touch.type == .direct, let screens, let window = screens.window, let view = touch.view,
                view.isDescendant(of: screens)
            else { return false }
            switch edge {
            case .right:
                // A drawing, a map, a game's 3D scene or board, and a slider keep a drag that
                // starts on them, even at the edge.
                guard point.x >= window.bounds.maxX - reach, !GameDragRegionView.holds(point)
                else { return false }
                return !touch.startsInView { view in
                    (view is PKCanvasView && view.isUserInteractionEnabled) || view is MKMapView
                        || view is MLNMapView || view is ARView || view is UISlider
                }
            case .left:
                // A screen pushed inside the chat, such as a report, keeps the system's back swipe.
                let stack = sequence(first: view as UIResponder, next: \.next)
                    .first { $0 is UINavigationController } as? UINavigationController
                return point.x <= window.bounds.minX + reach && (stack?.viewControllers.count ?? 0) <= 1
            }
        }

        /// The finger moves mostly away from the edge. A drag up or down at the edge still scrolls.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: nil)
            return ThreadChatPanGestureResolver.hasDirectionalHorizontalIntent(
                velocity: CGSize(width: velocity.x, height: velocity.y),
                direction: edge == .right ? .left : .right
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
