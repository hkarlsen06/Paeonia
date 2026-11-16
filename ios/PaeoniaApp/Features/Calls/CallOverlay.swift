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

private struct CallOverlayHost: ViewModifier {
    let center: CallCenter
    let participants: DailyChallengeParticipants

    @State private var starter: CallStarter
    @State private var model: CallOverlayModel
    @State private var window = CallOverlayWindowController()
    @Environment(\.profilePhotoImageProvider) private var photoProvider
    @Environment(\.avatarStyling) private var avatarStyling
    @Environment(\.threadChatContext) private var chatContext
    @Environment(\.callTurnOverride) private var turnOverride
    @Environment(\.callInitialPresentation) private var initialPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        followingTheCall(content)
            .environment(starter)
            .callNightCheck(starter)
            .onPreferenceChange(PaeoniaBannerBottomEdgeKey.self) { model.controlsTop = $0 }
            .onPreferenceChange(CallBubbleBottomEdgeKey.self) { model.panelTop = $0 }
            .onChange(of: participants) { _, participants in model.participants = participants }
            .onDockedKeyboardChange { model.keyboardIsUp = $0 }
            .onChange(of: model.callCover, initial: true) { _, cover in model.presence.callCover = cover }
            .onChange(of: model.layer, initial: true) { _, layer in window.show(layer) }
            .onAppear {
                model.followCalls()
                starter.overlay = model
                if initialPresentation == .small { model.minimize() }
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

    /// Gives the partner's shared screen the big spot, and says whether "Just us" can open.
    private func followingTheCall(_ content: Content) -> some View {
        content
            // The partner shares their screen to show it, so it fills the call screen.
            .onChange(of: center.session?.isPartnerSharingScreen == true) { _, isSharing in
                guard isSharing else { return }
                withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { model.stageOrder.showPartnerScreen() }
            }
            .onChange(of: chatContext.isAvailable, initial: true) { _, available in model.canOpenChat = available }
            .onChange(of: turnOverride, initial: true) { _, turn in model.turnOverride = turn }
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
        .onChange(of: model.center.session?.weakConnection) { _, side in
            guard let side else { return }
            AccessibilityNotification.Announcement(side == .mine
                ? String(localized: .callsWeakConnectionMine)
                : String(localized: .callsWeakConnectionPartner(model.participants.partnerName))).post()
        }
        // The full call screen follows how the phone is held, like the Camera app.
        .onChange(of: model.shownLayer == .screen, initial: true) { _, isScreen in
            if isScreen { model.deviceTurn.start() } else { model.deviceTurn.stop() }
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
                callout: model.presence.callCallout, openCallout: model.openCallout, minimize: model.minimize,
                stageOrder: Bindable(model).stageOrder, previewCorner: Bindable(model).previewCorner,
                canOpenChat: model.canOpenChat, deviceTurn: model.turn)
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
