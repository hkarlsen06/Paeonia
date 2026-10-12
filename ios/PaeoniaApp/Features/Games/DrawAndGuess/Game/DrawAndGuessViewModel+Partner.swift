import Foundation
import Observation
import PencilKit

// The partner: the heartbeat that says this screen is open, the invite, and the
// live room.
extension DrawAndGuessViewModel {
    // MARK: - Presence

    func beginHeartbeat() {
        heartbeatTask?.cancel()
        let gateway = gateway
        let interval = heartbeatInterval
        let sleep = sleep
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await gateway.setPresence(true)
                try? await sleep(interval)
            }
        }
    }

    func endHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        sendPresence(false)
    }

    func sendPresence(_ isPresent: Bool) {
        let gateway = gateway
        Task { try? await gateway.setPresence(isPresent) }
    }

    func updatePresenceState() {
        let isFresh = GamePresence.isFresh(state?.partnerLastSeenAt, now: now)
        switch live?.partnerActivity {
        case .drawing:
            partnerPresence = .drawing
        case .watching:
            partnerPresence = .watching
        case .choosing:
            partnerPresence = .choosing
        case .result:
            partnerPresence = .result
        case .present:
            partnerPresence = .here
        case .away, nil:
            partnerPresence = isFresh ? .here : .away
        }
        invite = GameInviteState.make(
            lastInviteAt: state?.lastInviteAt,
            localSentAt: localInviteSentAt,
            partnerIsHere: partnerPresence.isHere,
            now: now
        )
    }

    // MARK: - Invite

    /// "Tell [Name] you want to play". One invite every 15 minutes.
    func sendInvite() async {
        // The button may have come back since the last tick.
        now = dependencies.now()
        updatePresenceState()
        guard invite == .available else { return }
        let sentAt = dependencies.now()
        localInviteSentAt = sentAt
        recompute()
        do {
            let result = try await gateway.sendInvite()
            localInviteSentAt = result.sentAt
        } catch let error as PaeoniaConvexError {
            if case .server(code: "53300", message: _) = error {
                // The server already counted an invite in the last 15 minutes.
                return
            }
            localInviteSentAt = nil
            notice = .couldNotSendInvite
        } catch {
            localInviteSentAt = nil
            notice = .couldNotSendInvite
        }
        recompute()
    }

    // MARK: - Live room

    func attach(_ room: WidgetLiveDrawing) {
        room.applyRemoteDrawing = { _ in }
        room.savedStrokeKeys = { [] }
        room.setAsideDrawing = { _ in }
        room.currentDrawing = { [weak self] in self?.board.drawing ?? PKDrawing() }
        live = room
    }

    /// The drawer's canvas appeared. Connects it to the live room.
    func canvasReady(_ canvasView: PKCanvasView) {
        board.bindCanvasView(canvasView)
        live?.attach(to: canvasView)
    }

    func startLive() {
        guard let live else { return }
        live.start(drawing: board.drawing)
        liveObservationTask?.cancel()
        liveObservationTask = Task { [weak self] in
            let activity = Observations { live.partnerActivity }
            for await _ in activity {
                guard !Task.isCancelled, let self else { return }
                recompute()
            }
        }
    }

    func stopLive() {
        liveObservationTask?.cancel()
        liveObservationTask = nil
        live?.stop()
    }

    /// The partner is in the live room and drawing.
    var isPartnerDrawingLive: Bool {
        live?.partnerActivity == .drawing
    }

    /// Tells the partner's phone what this screen is doing.
    func syncLiveRole() {
        guard let live, let userID = currentUserID else { return }
        let isDrawerOfUnfinishedRound = round.map { $0.isDrawer(userID) && !$0.isFinished } ?? false
        live.switchRole(to: DrawAndGuessPhase.liveRole(
            phase: phase,
            isDrawerOfUnfinishedRound: isDrawerOfUnfinishedRound
        ))
    }

    /// What the drawer's result screen says about the sent drawing.
    var sentStatus: DrawAndGuessSentStatus {
        .make(partner: partnerPresence, guesserFirstSeenAt: round?.guesserFirstSeenAt)
    }

    /// This phone looks at an old result, and the partner already draws the next
    /// round. The result screen then offers "Watch [Name] draw".
    func updatePartnerStartedDrawing() {
        guard phase == .reveal, let userID = currentUserID,
              let current = state?.currentRound, current.id != round?.id
        else {
            partnerStartedDrawing = false
            return
        }
        partnerStartedDrawing = current.state == .drawing && current.drawerUserID != userID
    }
}
