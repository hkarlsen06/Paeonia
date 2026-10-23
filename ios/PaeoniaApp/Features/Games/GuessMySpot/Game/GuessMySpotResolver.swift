import Foundation

/// Where the person is in the game right now. Each case is one screen state.
nonisolated enum GuessMySpotPhase: Equatable, Sendable {
    /// Nothing is cached yet and the first read has not finished.
    case loading
    /// The couple has no game yet, or one is being made. The view model makes it.
    case starting
    /// This person picks a photo and checks its spot.
    case send
    /// The partner sent a photo and this person guesses where it was taken.
    case guess
    /// This person's photo waits for the partner's guess. `isQueued` is true while
    /// the send is only saved on this phone.
    case waitingForGuess(isQueued: Bool)
    /// The partner is picking a photo.
    case waitingForPhoto
    /// A guessed round whose reveal this person has not seen. `isHeld` is true
    /// while this person's guess is on its way and the real spot is not here yet.
    case reveal(isHeld: Bool)
}

nonisolated struct GuessMySpotResolution: Equatable, Sendable {
    var phase: GuessMySpotPhase
    /// The round of `guess`, `waitingForGuess` and `reveal`, with this phone's unsent moves applied.
    var round: RemoteGuessMySpotRound?
}

/// Works out the phase from the server's state and this phone's unsent moves.
/// It reads no clock and no network. A reveal counts as seen when the server has
/// this person's seen time for it, or a mark for it waits on this phone.
nonisolated struct GuessMySpotResolver: Sendable {
    let userID: UUID

    /// `hasLoaded` is true once a read has finished. `deferredReveals` are reveals
    /// this person stepped past while they were held, for this visit only.
    func resolve(
        state: RemoteGuessMySpotState?,
        hasLoaded: Bool,
        isStarting: Bool,
        pending: GuessMySpotPendingWork,
        deferredReveals: Set<UUID> = []
    ) -> GuessMySpotResolution {
        guard let state else {
            return GuessMySpotResolution(phase: hasLoaded ? .starting : .loading)
        }
        guard let game = state.game, !isStarting else {
            return GuessMySpotResolution(phase: .starting)
        }
        let rounds = apply(pending, to: state)
        if let unseen = rounds.first(where: { isUnseenReveal($0, pending, deferredReveals) }) {
            return GuessMySpotResolution(phase: .reveal(isHeld: unseen.spot == nil), round: unseen)
        }
        guard let newest = rounds.last else {
            return GuessMySpotResolution(phase: game.turnUserID == userID ? .send : .waitingForPhoto)
        }
        if !newest.isGuessed {
            if newest.senderUserID == userID {
                let isQueued = pending.sends.contains { $0.roundID == newest.id }
                return GuessMySpotResolution(phase: .waitingForGuess(isQueued: isQueued), round: newest)
            }
            return GuessMySpotResolution(phase: .guess, round: newest)
        }
        // The guesser of the newest round sends the next one.
        return GuessMySpotResolution(phase: newest.guesserUserID == userID ? .send : .waitingForPhoto)
    }

    /// The two newest rounds, oldest first, with the unsent guesses and sends applied.
    func apply(_ pending: GuessMySpotPendingWork, to state: RemoteGuessMySpotState) -> [RemoteGuessMySpotRound] {
        var rounds = [state.previousRound, state.currentRound].compactMap(\.self)
        for index in rounds.indices where !rounds[index].isGuessed {
            if let guess = pending.guesses[rounds[index].id], rounds[index].guesserUserID == userID {
                rounds[index].guess = guess
            }
        }
        for send in pending.sends where !rounds.contains(where: { $0.id == send.roundID }) {
            // A send only follows a round this person guessed, or starts the game,
            // and only for the next round. One left from a turn that moved on shows nowhere.
            let next = max(rounds.last?.roundNumber ?? 0, state.game?.roundCount ?? 0) + 1
            let isMyTurn = rounds.last.map { $0.isGuessed && $0.guesserUserID == userID }
                ?? (state.game?.turnUserID == userID)
            guard isMyTurn, send.details.roundNumber == next else { continue }
            rounds.append(queuedRound(send, state: state))
        }
        return rounds
    }

    /// A send the server has not seen yet. Its photo has no asset id, so the round
    /// names the round id there, and the photo loads from this phone.
    private func queuedRound(_ send: GuessMySpotSendPayload, state: RemoteGuessMySpotState) -> RemoteGuessMySpotRound {
        RemoteGuessMySpotRound(
            id: send.roundID,
            roundNumber: send.details.roundNumber,
            senderUserID: userID,
            guesserUserID: state.partnerUserID ?? userID,
            photoMediaAssetID: send.roundID,
            photoWidth: send.width,
            photoHeight: send.height,
            spotLatitude: send.details.spot.latitude,
            spotLongitude: send.details.spot.longitude,
            placeName: send.details.placeName,
            takenOn: send.details.takenOn,
            sentAt: send.createdAt
        )
    }

    private func isUnseenReveal(
        _ round: RemoteGuessMySpotRound,
        _ pending: GuessMySpotPendingWork,
        _ deferred: Set<UUID>
    ) -> Bool {
        round.isGuessed
            && (round.senderUserID == userID || round.guesserUserID == userID)
            && round.myRevealSeenAt == nil
            && !pending.seenReveals.contains(round.id)
            && !deferred.contains(round.id)
    }
}

nonisolated extension GuessMySpotResolver {
    /// It is this person's turn once the partner has sent a photo for them to guess.
    /// It reads the rounds and not the phase, so the turn also arrives while the last
    /// round's reveal is still on screen. Sending the next photo always follows this
    /// person's own guess, so it never counts as a handover.
    func attention(state: RemoteGuessMySpotState?, pending: GuessMySpotPendingWork) -> GameAttention {
        guard let state, state.game != nil, let newest = apply(pending, to: state).last,
              !newest.isGuessed, newest.guesserUserID == userID, newest.senderUserID != userID
        else {
            return GameAttention()
        }
        return GameAttention(turn: "round \(newest.id) sent")
    }
}

nonisolated extension GuessMySpotResolution {
    /// A photo to send, a guess, or a reveal waits for this person.
    var isYourTurn: Bool {
        switch phase {
        case .send, .guess, .reveal: true
        default: false
        }
    }
}
