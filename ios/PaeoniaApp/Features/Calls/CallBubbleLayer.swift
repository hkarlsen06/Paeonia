import SwiftUI

/// The small call over the app: the bubble, and while the partner shares their screen, a second
/// window with it. Each is a `CallFloatingWindow` of its own, so each moves, pinches and tucks away
/// on its own. The screen's window first shows beside the bubble, never on it. While the partner's
/// avatar is under the call, what the partner just did shows for a few seconds beside the bubble
/// (`CallNotices`), such as the game they opened, where a tap joins them, with the call's own news.
struct CallBubbleLayer: View {
    let model: CallOverlayModel
    let session: CallSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        reduceMotion ? nil : PaeoniaMotion.callOverlay
    }

    private var callout: PresenceCallout? {
        model.presence.callCallout
    }

    private var showsScreen: Bool {
        CallStageOrder.isShown(.partnerScreen, in: session)
    }

    var body: some View {
        GeometryReader { proxy in
            let placement = model.placement(in: proxy)
            ZStack {
                bubble(in: placement)
                if showsScreen, let screen = Binding(Bindable(model).screenWindow) {
                    screenWindow(screen, in: placement)
                }
            }
            .onChange(of: showsScreen, initial: true) { _, shows in
                model.screenWindow = shows
                    ? model.screenWindow ?? CallFloat(spot: placement.spot(
                        beside: model.bubbleFrame.isEmpty
                            ? nil : model.bubbleFrame.offsetBy(dx: 0, dy: -proxy.frame(in: .global).minY),
                        at: model.spot, size: CallScreenWindow.size(for: session)))
                    : nil
            }
        }
        .animation(motion, value: callout)
        .animation(motion, value: showsScreen)
        .animation(motion, value: session.isSharingScreen)
        .animation(motion, value: session.weakConnection)
        .animation(motion, value: session.cameraOffSuggestion)
    }

    private func bubble(in placement: CallBubblePlacement) -> some View {
        let partnerName = model.participants.partnerName
        return CallFloatingWindow(
            placement: placement, float: Bindable(model).bubble,
            zoomBase: CallBubble.showsVideo(session) ? CallBubble.videoSize(for: session) : nil,
            tabLabel: Text(.presenceTabAccessibilityLabel(partnerName)), tabIdentifier: "presence.tab",
            hasWaitingNotice: callout != nil,
            frameChanged: { model.bubbleFrame = $0 }, tabFrameChanged: { model.tabFrame = $0 }
        ) { scale, resize, tuck in
            CallBubble(
                center: model.center, session: session, participants: model.participants, videoScale: scale,
                resizeVideo: resize, tuck: tuck, open: { model.openFull(showing: .partner) })
        } notices: { _ in
            CallNotices(
                session: session, engine: model.center.engine, partnerName: partnerName, callout: callout,
                openCallout: model.openCallout, alignment: model.spot.isLeading ? .leading : .trailing)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.bubbleNoticesFrame = $0 }
        }
    }

    private func screenWindow(_ screen: Binding<CallFloat>, in placement: CallBubblePlacement) -> some View {
        let partnerName = model.participants.partnerName
        return CallFloatingWindow(
            placement: placement, float: screen, zoomBase: CallScreenWindow.size(for: session),
            tabLabel: Text(.callsScreenTab(partnerName)), tabIdentifier: "calls.screenWindow.tab",
            frameChanged: { model.screenFrame = $0 }, tabFrameChanged: { model.screenTabFrame = $0 }
        ) { scale, resize, tuck in
            CallScreenWindow(
                engine: model.center.engine, session: session, partnerName: partnerName, scale: scale,
                resize: resize, tuck: tuck, open: { model.openFull(showing: .partnerScreen) })
        } notices: { _ in
            EmptyView()
        }
    }
}

/// The partner's shared screen in a window of its own over the app, in the shape of their screen.
/// A tap opens the call screen with it filling the screen.
struct CallScreenWindow: View {
    let engine: any CallEngineActions
    let session: CallSession
    let partnerName: String
    let scale: CGFloat
    let resize: (AccessibilityAdjustmentDirection) -> Void
    let tuck: () -> Void
    let open: () -> Void

    /// Before a pinch, as much area as the bubble's video, in the shape of the partner's screen.
    static func size(for session: CallSession) -> CGSize {
        let area: CGFloat = 104 * 148
        let ratio = session.partnerScreenAspectRatio ?? 9 / 19.5
        return CGSize(width: (area * ratio).squareRoot(), height: (area / ratio).squareRoot())
    }

    var body: some View {
        let size = Self.size(for: session)
        CallVideoView(engine: engine, source: .partnerScreen)
            .frame(width: size.width * scale, height: size.height * scale)
            .clipShape(.rect(cornerRadius: PaeoniaRadius.radius20))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20).strokeBorder(.white.opacity(0.25))
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .contentShape(.rect(cornerRadius: PaeoniaRadius.radius20))
            .onTapGesture(perform: open)
            .accessibilityElement()
            .accessibilityLabel(Text(.callsPartnerScreen(partnerName)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityAction(named: Text(.presenceActionTuck), tuck)
            .accessibilityAdjustableAction(resize)
            .accessibilityIdentifier("calls.screenWindow")
    }
}
