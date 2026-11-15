import Observation
import SwiftUI
import UIKit

extension View {
    /// Mounts the call screen, the bubble and the ring pill once for the signed-in app, in a window
    /// of their own above every screen, sheet and cover, and puts the `CallStarter` for the phone
    /// buttons in the environment. Does nothing without a `CallCenter` in the environment.
    func callOverlay(participants: DailyChallengeParticipants) -> some View {
        modifier(CallOverlayMount(participants: participants))
    }

    /// Where the bubble must stay above, in global coordinates, such as the top of the game chat
    /// panel. The bubble also stays above the bottom controls that `paeoniaBannerBottomEdge` reports.
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

    @Environment(CallCenter.self) private var center: CallCenter?
    /// A developer scenario brings its own, with the night question already up.
    @Environment(CallStarter.self) private var injectedStarter: CallStarter?

    func body(content: Content) -> some View {
        if let center {
            content.modifier(CallOverlayHost(center: center, starter: injectedStarter, participants: participants))
        } else {
            content
        }
    }
}

/// What the overlay window shows, and where the bubble may go.
@MainActor
@Observable
final class CallOverlayModel {
    enum Layer: Equatable {
        case hidden
        case screen
        case bubble
        /// The partner's call ringing inside the app, as a pill at the top of the screen.
        case ring
    }

    let center: CallCenter
    var participants: DailyChallengeParticipants
    /// The top of the screen's bottom controls (`PaeoniaBannerBottomEdgeKey`), in global coordinates.
    var controlsTop: CGFloat?
    /// The top of the game chat panel while it is open (`CallBubbleBottomEdgeKey`).
    var panelTop: CGFloat?
    /// The corner the person dragged the bubble to.
    var corner = CallBubbleCorner.topTrailing
    /// Where the bubble is in the window, so touches beside it reach the app underneath.
    var bubbleFrame = CGRect.zero
    /// Where the ring pill is in the window, for the same reason.
    var ringFrame = CGRect.zero
    /// The last call the overlay showed, so the screen, the bubble or the pill can leave on screen
    /// after the engine clears the call.
    var lastSession: CallSession?
    /// The layer the window draws. It follows `layer` once the window shows, because a view that
    /// appears in a hidden window skips its transition.
    var shownLayer = Layer.hidden

    init(center: CallCenter, participants: DailyChallengeParticipants) {
        self.center = center
        self.participants = participants
    }

    /// An incoming call that rings on the system call UI shows nothing in the app. One that rings
    /// inside the app shows as the ring pill until the person opens the full call screen.
    var layer: Layer {
        guard let session = center.session else { return .hidden }
        if session.direction == .incoming, session.phase == .ringing, !session.ringsInApp { return .hidden }
        guard center.presentation == .bubble else { return .screen }
        return session.ringsInApp ? .ring : .bubble
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

    init(center: CallCenter, starter: CallStarter?, participants: DailyChallengeParticipants) {
        self.center = center
        self.participants = participants
        _starter = State(initialValue: starter ?? CallStarter(center: center))
        _model = State(initialValue: CallOverlayModel(center: center, participants: participants))
    }

    func body(content: Content) -> some View {
        content
            .environment(starter)
            .callNightCheck(starter)
            .onPreferenceChange(PaeoniaBannerBottomEdgeKey.self) { model.controlsTop = $0 }
            .onPreferenceChange(CallBubbleBottomEdgeKey.self) { model.panelTop = $0 }
            .onChange(of: participants) { _, participants in model.participants = participants }
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
                window.install(
                    CallOverlayRoot(model: model)
                        .environment(\.profilePhotoImageProvider, photoProvider)
                        .environment(\.avatarStyling, avatarStyling),
                    model: model
                )
                window.show(model.layer)
            }
            .onDisappear { window.remove() }
            .task { center.engine.refreshCallContext() }
    }
}

/// The call screen, the bubble or the ring pill, in the overlay window.
private struct CallOverlayRoot: View {
    let model: CallOverlayModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            layers(screenTravel: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12), value: model.shownLayer)
        .preferredColorScheme(.dark)
    }

    /// `screenTravel` is the window's whole height. The call screen's background reaches under
    /// the home indicator, so sliding it by its own height would leave a strip on screen.
    private func layers(screenTravel: CGFloat) -> some View {
        ZStack {
            if let session = model.center.session ?? model.lastSession {
                switch model.shownLayer {
                case .screen:
                    CallScreen(center: model.center, session: session, participants: model.participants)
                        .transition(reduceMotion ? .opacity : .offset(y: screenTravel))
                case .bubble:
                    CallBubbleLayer(model: model, session: session)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                case .ring:
                    CallRingLayer(model: model, session: session)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                case .hidden:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Puts the overlay in a window of its own above the app's, below the app lock's cover. The
/// window takes touches only on the bubble or the ring pill while the call is small, so the app
/// under it works.
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
        case .bubble, .ring:
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
        switch model?.layer {
        case .screen: true
        case .bubble: model?.bubbleFrame.contains(point) == true
        case .ring: model?.ringFrame.contains(point) == true
        case .hidden, nil: false
        }
    }
}
