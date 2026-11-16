import Observation
import SwiftUI

/// Where the partner's call rings inside the app.
nonisolated enum RingAnchor: Equatable, Sendable {
    /// Under the status bar and the Dynamic Island.
    case top
    /// Grown out of the partner's avatar at its spot.
    case avatar(CallBubbleSpot)
}

/// How the call shows inside the app: the full call screen, or small over the other screens, as the
/// floating bubble or, while the partner's call rings in the app, the ring pill.
nonisolated enum CallPresentation: Equatable, Sendable {
    case full
    case small

    /// What the call shows after `old` became `new`. A new call opens the full call screen, except a
    /// ring inside the app, which starts small as the ring pill. A ring that stops ringing inside the
    /// app, because the person answered it or it went to the system's call UI, opens the full call
    /// screen too, where the call shows once it connects. Any other change keeps `current`, which the
    /// person chose.
    static func after(_ old: CallSession?, _ new: CallSession?, current: Self) -> Self {
        guard let new else { return current }
        if new.id != old?.id { return new.ringsInApp ? .small : .full }
        if old?.ringsInApp == true, !new.ringsInApp { return .full }
        return current
    }
}

extension EnvironmentValues {
    /// Starts a developer scenario's call small or full, in place of where a new call starts.
    @Entry var callInitialPresentation: CallPresentation?
}

/// What the overlay window shows, and where the bubble may go. It owns whether the call shows full
/// or small, which follows the call (`CallPresentation.after`) and the person's taps.
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
    /// Where the bubble sits, how much bigger or smaller than `CallBubble.videoSize(for:)` the person
    /// pinched its video, and whether they pushed it into the side of the screen at `spot.edge`, where
    /// it waits as a tab. It comes back out each time the call shrinks to the bubble again.
    var bubble = CallFloat(spot: .initial)
    /// Where the person dragged the bubble or the partner's avatar to. They share it.
    var spot: CallBubbleSpot {
        get { bubble.spot }
        set { bubble.spot = newValue }
    }
    /// The window with the partner's shared screen over the app, placed beside the bubble the first
    /// time it shows during a share. Nil while the partner shares nothing.
    var screenWindow: CallFloat?
    /// Which video fills the call screen. Each call starts over.
    var stageOrder = CallStageOrder()
    /// The corner of the call screen the person dragged the previews to.
    var previewCorner = CallPreviewCorner.initial
    /// The app has a couple, so "Just us" can open from the call.
    var canOpenChat = false
    /// How the person holds the phone, which the full call screen follows during video.
    let deviceTurn = CallDeviceTurn()
    /// A developer scenario's pinned turn, in place of `deviceTurn`.
    var turnOverride: CallTurn?
    /// Where the ring pill shows, decided as it comes on screen so it never moves while it rings.
    private(set) var ringAnchor = RingAnchor.top
    /// Where each part is in the window, for `touchArea`. Each has its own, so one that is leaving
    /// can't move another's.
    var bubbleFrame = CGRect.zero
    /// The call's news and what the partner just did, beside the bubble (`CallNotices`).
    var bubbleNoticesFrame = CGRect.zero
    var screenFrame = CGRect.zero
    var screenTabFrame = CGRect.zero
    var ringFrame = CGRect.zero
    /// The partner's avatar with its notice and toolbar.
    var avatarFrame = CGRect.zero
    /// The tab at the edge while the avatar or the bubble is tucked away.
    var tabFrame = CGRect.zero
    /// The last call the overlay showed, so the screen, the bubble or the pill can leave on screen
    /// after the engine clears the call.
    private(set) var lastSession: CallSession?
    private(set) var presentation: CallPresentation
    /// The layer the window draws. It follows `layer` once the window shows, because a view that
    /// appears in a hidden window skips its transition.
    var shownLayer = Layer.hidden {
        didSet {
            previousShownLayer = oldValue
            if shownLayer != .bubble {
                bubble.isTucked = false
                screenWindow?.isTucked = false
            }
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
        lastSession = center.session
        presentation = .after(nil, center.session, current: .full)
    }

    /// Follows each change to the call from now on, in the same change, starting with a call that
    /// began between this model's creation and now.
    func followCalls() {
        center.sessionDidChange = { [weak self] old, new in self?.sessionChanged(from: old, to: new) }
        if center.session != lastSession { sessionChanged(from: lastSession, to: center.session) }
    }

    /// Each new call starts over with its videos in their first order.
    private func sessionChanged(from old: CallSession?, to new: CallSession?) {
        guard let new else { return }
        lastSession = new
        if new.id != old?.id { stageOrder = CallStageOrder() }
        presentation = .after(old, new, current: presentation)
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
        guard presentation == .small else { return .screen }
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

    var turn: CallTurn {
        turnOverride ?? deviceTurn.turn
    }

    func showFull() {
        presentation = .full
    }

    /// Shrinks the call to its bubble, or to the ring pill while the partner's call rings in the app.
    func minimize() {
        presentation = .small
    }

    /// Opens the full call screen from a small window, with that window's video filling it.
    func openFull(showing source: CallVideoSource) {
        if let session = center.session { stageOrder.bringForward(source, in: session) }
        presentation = .full
    }

    /// Opens what the call's callout is about, or "Just us" from the call screen's message button.
    /// The call shrinks to its bubble, so what opens shows under it, and the covers over the app close
    /// first.
    func openCallout(_ destination: PresenceDestination) {
        presentation = .small
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
            .frames(smallCallFrames)
        case .ring: .frame(ringFrame)
        case .presence:
            switch presence.mode {
            case .avatar: .frame(avatarFrame)
            case .expanded: .everywhere
            case .tucked: .frame(tabFrame)
            }
        }
    }

    /// The bubble or its tab, its notices, and the screen's window or its tab.
    private var smallCallFrames: [CGRect] {
        var frames = [bubble.isTucked ? tabFrame : bubbleFrame]
        if let session = center.session ?? lastSession, !bubble.isTucked,
           CallNotices.showsAny(session, callout: presence.callCallout) {
            frames.append(bubbleNoticesFrame)
        }
        if let screenWindow { frames.append(screenWindow.isTucked ? screenTabFrame : screenFrame) }
        return frames
    }

    func placement(in proxy: GeometryProxy) -> CallBubblePlacement {
        CallBubblePlacement(
            size: proxy.size, globalMinY: proxy.frame(in: .global).minY, controlsTop: controlsTop, panelTop: panelTop,
            keyboardIsUp: keyboardIsUp)
    }
}
