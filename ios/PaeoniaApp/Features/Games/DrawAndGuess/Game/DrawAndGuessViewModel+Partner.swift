import Foundation
import Observation
import PencilKit

// The partner: the heartbeat that says this screen is open, the invite, and the
// live room.
extension DrawAndGuessViewModel {
    // MARK: - Presence

    func updatePresenceState() {
        let isHeartbeatHere = state?.partnerPresent == true
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
            partnerPresence = isHeartbeatHere ? .here : .away
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
            let result = try await gateway.sendInvite(.drawAndGuess)
            localInviteSentAt = result.sentAt
        } catch let error as PaeoniaConvexError {
            if case .server(code: "53300", message: _) = error {
                // The server already counted an invite in the last 15 minutes.
                return
            }
            localInviteSentAt = nil
            notice = .couldNotSendInvite(PaeoniaFailure(error))
        } catch {
            localInviteSentAt = nil
            notice = .couldNotSendInvite(PaeoniaFailure(error))
        }
        recompute()
    }

    // MARK: - Live room

    func attach(_ room: WidgetLiveDrawing) {
        room.applyRemoteDrawing = { _ in }
        room.savedStrokeKeys = { [] }
        room.setAsideDrawing = { _ in }
        room.currentDrawing = { [weak self] in self?.board.drawing ?? PKDrawing() }
        room.onPartnerArrived = { [weak self] in self?.resendGuessScreen() }
        let channel = GameLiveChannel<DrawAndGuessLiveMessage>(connection: room.connection)
        channel.onMessage = { [weak self] message in self?.receiveGuessScreen(message) }
        liveGuessChannel = channel
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
            let activity = Observations { (live.partnerActivity, live.hasPartnerStrokes) }
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

    var isPartnerDrawingLive: Bool {
        live?.partnerActivity == .drawing
    }

    /// This phone shows a result and picks the next word, and the partner's
    /// phone is in the room on a screen with nothing to do, so it waits for this one.
    var isPartnerWaitingForMe: Bool {
        phase == .reveal && isNextTurnMine && live?.partnerActivity == .present
    }

    /// This phone shows a result, and the partner picks the next word. The
    /// result screen says so until "Watch [Name] draw" takes over.
    var isPartnerChoosingNextWord: Bool {
        phase == .reveal && !isNextTurnMine && partnerNextRound == nil && partnerPresence == .choosing
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
        .make(
            partner: partnerPresence,
            guesserFirstSeenAt: round?.guesserFirstSeenAt,
            isPartnerWatchingLive: live?.hasSentCanvasToPartner == true,
            isWaitingToSend: isWaitingToSend
        )
    }

    /// This phone looks at an old result, and the partner already draws the next
    /// round or has sent it. The result screen then offers to go to it.
    func updatePartnerNextRound() {
        guard phase == .reveal, let userID = currentUserID,
              let current = state?.currentRound, current.id != round?.id,
              current.drawerUserID != userID
        else {
            partnerNextRound = nil
            return
        }
        partnerNextRound = switch current.state {
        case .drawing: .drawing
        case .guessing: .sent
        case .solved, .missed: nil
        }
    }
}

/// Where the partner is in the round after the one on this phone's result screen.
enum DrawAndGuessPartnerNextRound: Equatable {
    /// "Watch [Name] draw".
    case drawing
    /// "See what [Name] drew".
    case sent
}
