import Observation
import SwiftUI
import UIKit

extension View {
    /// Mounts the call screen and the bubble once for the signed-in app, in a window of their own
    /// above every screen, sheet and cover, and puts the `CallStarter` for the phone buttons in the
    /// environment. Does nothing without a `CallCenter` in the environment.
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

    init(center: CallCenter, participants: DailyChallengeParticipants) {
        self.center = center
        self.participants = participants
    }

    /// An incoming call that still rings shows nothing in the app, because the system shows it.
    /// The simulator has no system call UI, so there the call screen answers it.
    var layer: Layer {
        guard let session = center.session else { return .hidden }
        #if !targetEnvironment(simulator)
        if session.direction == .incoming, session.phase == .ringing { return .hidden }
        #endif
        return center.presentation == .full ? .screen : .bubble
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
            // Starting or answering a call opens the full call screen.
            .onChange(of: center.session?.id) { oldID, newID in
                if let newID, newID != oldID { center.presentation = .full }
            }
            .onChange(of: model.layer, initial: true) { _, layer in window.show(layer) }
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
    }
}

/// The call screen or the bubble, in the overlay window.
private struct CallOverlayRoot: View {
    let model: CallOverlayModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let session = model.center.session {
                switch model.layer {
                case .screen:
                    CallScreen(center: model.center, session: session, participants: model.participants)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                case .bubble:
                    CallBubbleLayer(model: model, session: session)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                case .hidden:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.12), value: model.layer)
        .preferredColorScheme(.dark)
    }
}

/// Puts the overlay in a window of its own above the app's, below the app lock's cover. The
/// window takes touches only on the bubble while the call is small, so the app under it works.
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
        guard let window else { return }
        hideTask?.cancel()
        window.rootViewController?.view.accessibilityViewIsModal = layer == .screen
        switch layer {
        case .hidden:
            // After the screen or bubble has left.
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                window.isHidden = true
            }
        case .screen:
            // The keyboard sits above every window.
            PaeoniaKeyboard.dismiss()
            window.isHidden = false
            UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view)
        case .bubble:
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
        case .hidden, nil: false
        }
    }
}
