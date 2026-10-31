import Foundation

// The partner: the heartbeat that says this screen is open, what their phone
// says they are doing, and the invite.
extension ExquisiteCorpseViewModel {
    func makeContinuation() -> GameContinuation? {
        guard phase == .reveal, let figure, let game = state?.game, let userID = currentUserID else { return nil }
        if let next = state?.currentFigure, next.number > figure.number,
           let head = next.part(at: ExquisiteCorpsePartKind.head.rawValue), head.drawerUserID != userID {
            return GameContinuation(id: "figure \(next.id) head sent", status: .drew)
        }
        if figure.starterUserID != userID, live?.partnerActivity == .watching,
           game.figureNumber == figure.number + 1, game.partIndex == ExquisiteCorpsePartKind.head.rawValue {
            return GameContinuation(id: "figure \(figure.id) partner waiting", status: .waiting)
        }
        return nil
    }

    // MARK: - Presence

    /// Reads what the partner is doing from the relay room, and from their
    /// heartbeat when the room says nothing, then works out the invite button.
    func updatePresenceState() {
        let shared = overview?.presence(for: .exquisiteCorpse)
        partnerPresence = ExquisiteCorpsePartnerPresence(
            live?.partnerActivity ?? .away,
            isHeartbeatFresh: shared?.partnerPresent == true
        )
        invite = GameInviteState.make(
            lastInviteAt: shared?.lastInviteAt,
            localSentAt: localInviteSentAt,
            partnerIsHere: partnerPresence.isHere,
            now: now
        )
        // A partner who starts watching on a connection that was already open
        // missed the strip, because the room only reports a new socket.
        if partnerPresence == .watching, lastPartnerPresence != .watching {
            resendLiveState()
        }
        lastPartnerPresence = partnerPresence
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
            let result = try await dependencies.gateway.sendInvite(.exquisiteCorpse)
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
}
