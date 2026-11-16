import Observation
import SwiftUI
import UIKit

extension View {
    /// Mounts the call screen, the bubble and the ring pill once for the signed-in app, in a window
    /// of their own above every screen, sheet and cover, and puts the `CallStarter` for the phone
    /// buttons in the environment. While no call is up the window shows the partner's avatar, while
    /// `presence` says the partner is here. Does nothing without a `CallCenter` in the environment.
    func callOverlay(participants: DailyChallengeParticipants, presence: PartnerPresenceModel) -> some View {
        modifier(CallOverlayMount(participants: participants, presence: presence))
    }

    /// Where the bubble must stay above, in global coordinates, such as the top of the game chat
    /// panel. The bubble also stays above the bottom controls that `paeoniaBannerBottomEdge` reports,
    /// such as a chat's composer.
    func callBubbleBottomEdge(_ edge: CGFloat?) -> some View {
        preference(key: CallBubbleBottomEdgeKey.self, value: edge)
    }
}

struct CallBubbleBottomEdgeKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        guard let next = nextValue() else { return }
        value = value.map { min($0, next) } ?? next
    }
}

private struct CallOverlayMount: ViewModifier {
    let participants: DailyChallengeParticipants
    let presence: PartnerPresenceModel

    @Environment(CallCenter.self) private var center: CallCenter?
    /// A developer scenario brings its own, with the night question already up.
    @Environment(CallStarter.self) private var injectedStarter: CallStarter?

    func body(content: Content) -> some View {
        if let center {
            content.modifier(CallOverlayHost(
                center: center, starter: injectedStarter, participants: participants, presence: presence))
        } else {
            content
        }
    }
}

/// Where the partner's call rings inside the app.
nonisolated enum RingAnchor: Equatable, Sendable {
    /// Under the status bar and the Dynamic Island.
    case top
    /// Grown out of the partner's avatar at its spot.
    case avatar(CallBubbleSpot)
}

/// What the overlay window shows, and where the bubble may go.
@MainActor
@Observable
final class CallOverlayModel {
    enum Layer: Equatable {
        case hidden
        case screen
        case bubble
        /// The partner's call ringing inside the app, as a pill (`ringAnchor`).
        case ring
        /// No call, and the partner is here: their avatar at its spot (`PresencePillLayer`).
        case presence
    }

    /// Where the window takes touches. Everywhere else they reach the app underneath.
    enum TouchArea: Equatable {
        case none
        case everywhere
        case frames([CGRect])

        static func frame(_ frame: CGRect) -> Self {
            .frames([frame])
        }

        func contains(_ point: CGPoint) -> Bool {
            switch self {
            case .none: false
            case .everywhere: true
            case let .frames(frames): frames.contains { $0.contains(point) }
            }
        }
    }

    let center: CallCenter
    let presence: PartnerPresenceModel
    var participants: DailyChallengeParticipants
    /// The top of the screen's bottom controls (`PaeoniaBannerBottomEdgeKey`), in global coordinates.
    var controlsTop: CGFloat?
    /// The top of the game chat panel while it is open (`CallBubbleBottomEdgeKey`).
    var panelTop: CGFloat?
    /// Where the person dragged the bubble or the partner's avatar to. They share it.
    var spot = CallBubbleSpot.initial
    /// How much bigger or smaller than `CallBubble.videoSize(for:)` the person pinched the video bubble.
    var videoScale: CGFloat = 1
    /// The corner of the call screen the person dragged their own camera to.
    var ownCameraCorner = CallOwnCameraCorner.initial
    /// The person pushed the bubble into the side of the screen at `spot.edge`, where it waits as a
    /// tab. It comes back out each time the call shrinks to the bubble again.
    var bubbleIsTucked = false
    /// Where the ring pill shows, decided as it comes on screen so it never moves while it rings.
    private(set) var ringAnchor = RingAnchor.top
    /// Where each part is in the window, for `touchArea`. Each has its own, so one that is leaving
    /// can't move another's.
    var bubbleFrame = CGRect.zero
    /// What the partner just did, beside the bubble (`CallCallout`).
    var bubbleCalloutFrame = CGRect.zero
    var ringFrame = CGRect.zero
    /// The partner's avatar with its notice and toolbar.
    var avatarFrame = CGRect.zero
    /// The tab at the edge while the avatar or the bubble is tucked away.
    var tabFrame = CGRect.zero
    /// The last call the overlay showed, so the screen, the bubble or the pill can leave on screen
    /// after the engine clears the call.
    var lastSession: CallSession?
    /// The layer the window draws. It follows `layer` once the window shows, because a view that
    /// appears in a hidden window skips its transition.
    var shownLayer = Layer.hidden {
        didSet {
            previousShownLayer = oldValue
            if shownLayer != .bubble { bubbleIsTucked = false }
            if shownLayer == .ring, oldValue != .ring { ringAnchor = currentRingAnchor }
        }
    }
    /// The layer the window drew before, so the call screen and the ring pill can tell a morph
    /// between them from an entrance.
    private(set) var previousShownLayer = Layer.hidden

    init(
        center: CallCenter, participants: DailyChallengeParticipants, presence: PartnerPresenceModel
    ) {
        self.center = center
        self.participants = participants
        self.presence = presence
    }

    var layer: Layer {
        callLayer ?? (presence.isShown ? .presence : .hidden)
    }

    /// The call's layer, which always wins over the partner's avatar. Nil while no call shows in the
    /// app. An incoming call that rings on the system call UI shows none, and one that rings inside
    /// the app shows as the ring pill until the person opens the full call screen.
    var callLayer: Layer? {
        guard let session = center.session else { return nil }
        if session.direction == .incoming, session.phase == .ringing, !session.ringsInApp { return nil }
        guard center.presentation == .bubble else { return .screen }
        return session.ringsInApp ? .ring : .bubble
    }

    /// The full call screen says the partner's news only while the call is under way. While it
    /// rings, connects or has ended, the news goes where it goes beside a small call.
    var callCover: PresenceCallCover {
        guard let callLayer else { return .none }
        switch (callLayer, center.session?.phase) {
        case (.screen, .active), (.screen, .reconnecting): return .fullScreen
        default: return .small
        }
    }

    /// Opens what the call's callout is about. The call shrinks to its bubble, so what opens shows
    /// under it, and the covers over the app close first.
    func openCallout(_ destination: PresenceDestination) {
        center.presentation = .bubble
        AppCovers.close { [presence] in
            presence.clearCallNotice()
            presence.open(destination)
        }
    }

    /// The keyboard is up. It sits above this window and could cover a ring at the avatar, so a ring
    /// that is already there moves to the top.
    var keyboardIsUp = false {
        didSet { if keyboardIsUp, shownLayer == .ring { ringAnchor = .top } }
    }

    /// The ring grows out of the partner's avatar while it shows at its spot, and else rings at the
    /// top of the screen, as when the avatar is tucked at an edge, the partner is not here, or the
    /// keyboard is up.
    private var currentRingAnchor: RingAnchor {
        guard presence.isShown, !keyboardIsUp else { return .top }
        if case .tucked = presence.mode { return .top }
        return .avatar(spot)
    }

    /// The partner's avatar comes back once the call has gone, so an ended call's screen or ring pill
    /// shrinks into it.
    func endsIntoPresence(_ session: CallSession) -> Bool {
        guard case .ended = session.phase else { return false }
        return presence.isShown
    }

    /// The part the window draws takes the touches. While the avatar's toolbar is open the window
    /// takes every touch, so a tap outside the toolbar closes it and goes no further.
    var touchArea: TouchArea {
        switch shownLayer {
        case .hidden: .none
        case .screen: .everywhere
        case .bubble:
            if bubbleIsTucked {
                .frame(tabFrame)
            } else if presence.callCallout != nil {
                .frames([bubbleFrame, bubbleCalloutFrame])
            } else {
                .frame(bubbleFrame)
            }
        case .ring: .frame(ringFrame)
        case .presence:
            switch presence.mode {
            case .avatar: .frame(avatarFrame)
            case .expanded: .everywhere
            case .tucked: .frame(tabFrame)
            }
        }
    }

    func placement(in proxy: GeometryProxy) -> CallBubblePlacement {
        CallBubblePlacement(
            size: proxy.size, globalMinY: proxy.frame(in: .global).minY, controlsTop: controlsTop, panelTop: panelTop,
            keyboardIsUp: keyboardIsUp)
    }
}

private struct CallOverlayHost: ViewModifier {
    let center: CallCenter
    let participants: DailyChallengeParticipants

    @State private var starter: CallStarter
    @State private var model: CallOverlayModel
    @State private var window = CallOverlayWindowController()
    @Environment(\.profilePhotoImageProvider) private var photoProvider
    @Environment(\.avatarStyling) private var avatarStyling

    init(
        center: CallCenter, starter: CallStarter?, participants: DailyChallengeParticipants,
        presence: PartnerPresenceModel
    ) {
        self.center = center
        self.participants = participants
        _starter = State(initialValue: starter ?? CallStarter(center: center))
        _model = State(initialValue: CallOverlayModel(
            center: center, participants: participants, presence: presence))
    }

    func body(content: Content) -> some View {
        content
            .environment(starter)
            .callNightCheck(starter)
            .onPreferenceChange(PaeoniaBannerBottomEdgeKey.self) { model.controlsTop = $0 }
            .onPreferenceChange(CallBubbleBottomEdgeKey.self) { model.panelTop = $0 }
            .onChange(of: participants) { _, participants in model.participants = participants }
            .onDockedKeyboardChange { model.keyboardIsUp = $0 }
            .onChange(of: model.callCover, initial: true) { _, cover in model.presence.callCover = cover }
            // Starting or answering a call opens the full call screen. A ring inside the app starts
            // as the pill.
            .onChange(of: center.session?.id) { oldID, newID in
                if let newID, newID != oldID, center.session?.ringsInApp != true { center.presentation = .full }
            }
            .onChange(of: model.layer, initial: true) { _, layer in window.show(layer) }
            .onChange(of: center.session) { _, session in
                if let session { model.lastSession = session }
            }
            .onAppear {
                let root = CallOverlayRoot(model: model)
                    .environment(starter)
                    .environment(\.profilePhotoImageProvider, photoProvider)
                    .environment(\.avatarStyling, avatarStyling)
                    #if DEBUG
                    // A window of its own does not get the app window's fixture.
                    .modifier(DeveloperAssistiveTechnologyEnvironment())
                    #endif
                window.install(root, model: model)
                window.show(model.layer)
            }
            .onDisappear { window.remove() }
            .task { center.engine.refreshCallContext() }
    }
}

/// The call screen, the bubble, the ring pill or the partner's avatar, in the overlay window.
private struct CallOverlayRoot: View {
    let model: CallOverlayModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph

    var body: some View {
        GeometryReader { proxy in
            layers(screenTravel: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
        }
        .environment(\.callMorph, morph)
        .animation(reduceMotion ? nil : PaeoniaMotion.callOverlay, value: model.shownLayer)
        .preferredColorScheme(.dark)
        // The window's layer stays the same, so VoiceOver hears of the call's callout only from here.
        .onChange(of: model.presence.callCallout) { _, callout in
            guard let callout else { return }
            AccessibilityNotification.Announcement(
                callout.accessibilityLabel(partnerName: model.participants.partnerName)
            ).post()
        }
    }

    /// `screenTravel` is the window's whole height. The call screen's background reaches under
    /// the home indicator, so sliding it by its own height would leave a strip on screen.
    private func layers(screenTravel: CGFloat) -> some View {
        ZStack {
            switch model.shownLayer {
            case .presence:
                PresencePillLayer(overlay: model)
                    .transition(.opacity)
            case .screen, .bubble, .ring:
                if let session = model.center.session ?? model.lastSession {
                    callLayer(session, screenTravel: screenTravel)
                }
            case .hidden:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func callLayer(_ session: CallSession, screenTravel: CGFloat) -> some View {
        // While the call rings inside the app, the pill and the call screen morph into each other:
        // the one leaving fades while their shared parts (`CallMorphPart`) move. The partner's
        // avatar's photo grows into either, and an ended call shrinks back into it. A view that
        // leaves keeps the transition of its last update, so the leaving side reads the ring or
        // the call's end, and the arriving side reads the layer it replaces.
        let leavesByMorph = reduceMotion || (session.ringsInApp && session.phase == .ringing)
            || model.endsIntoPresence(session)
        switch model.shownLayer {
        case .screen:
            CallScreen(
                center: model.center, session: session, participants: model.participants,
                callout: model.presence.callCallout, openCallout: model.openCallout,
                ownCameraCorner: Bindable(model).ownCameraCorner)
                .transition(.asymmetric(
                    insertion: arrives(from: .ring) || arrives(from: .presence) ? .opacity : .offset(y: screenTravel),
                    removal: leavesByMorph ? .opacity : .offset(y: screenTravel)
                ))
        case .bubble:
            CallBubbleLayer(model: model, session: session)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
        case .ring:
            // A pill at the avatar never travels in from the top edge.
            let slide: AnyTransition = model.ringAnchor == .top
                ? .move(edge: .top).combined(with: .opacity) : .opacity
            CallRingLayer(model: model, session: session)
                .transition(.asymmetric(
                    insertion: arrives(from: .screen) || arrives(from: .presence) ? .opacity : slide,
                    removal: leavesByMorph ? .opacity : slide
                ))
        case .presence, .hidden:
            EmptyView()
        }
    }

    private func arrives(from layer: CallOverlayModel.Layer) -> Bool {
        reduceMotion || model.previousShownLayer == layer
    }
}

/// Puts the overlay in a window of its own above the app's, below the app lock's cover. The
/// window takes touches only on the bubble, the ring pill or the partner's avatar while the call is
/// small or there is none, so the app under it works.
@MainActor
final class CallOverlayWindowController {
    private var window: CallOverlayWindow?
    private var hideTask: Task<Void, Never>?

    func install(_ root: some View, model: CallOverlayModel) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.overrideUserInterfaceStyle = .dark
        let window = CallOverlayWindow(windowScene: scene)
        window.model = model
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = true
        self.window = window
    }

    func show(_ layer: CallOverlayModel.Layer) {
        guard let window, let model = window.model else { return }
        hideTask?.cancel()
        if layer == .hidden || !window.isHidden {
            model.shownLayer = layer
        } else {
            // The window shows first, so the layer's entrance animates.
            DispatchQueue.main.async { if model.layer == layer { model.shownLayer = layer } }
        }
        window.rootViewController?.view.accessibilityViewIsModal = layer == .screen
        switch layer {
        case .hidden:
            // After the screen, the bubble or the pill has left. A full screen slides the
            // whole height, and its spring is still settling at 400 ms.
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                window.isHidden = true
            }
        case .screen:
            // The keyboard sits above every window.
            PaeoniaKeyboard.dismiss()
            window.isHidden = false
            UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)
        case .bubble, .ring, .presence:
            window.isHidden = false
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    func remove() {
        hideTask?.cancel()
        window?.isHidden = true
        window = nil
    }
}

private final class CallOverlayWindow: UIWindow {
    var model: CallOverlayModel?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        model?.touchArea.contains(point) ?? false
    }
}
