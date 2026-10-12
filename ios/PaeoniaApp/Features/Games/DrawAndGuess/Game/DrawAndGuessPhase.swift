import Foundation

/// Where the person is in the game right now. Each case is one screen state.
/// `DrawAndGuessViewModel` holds the details that go with it.
nonisolated enum DrawAndGuessPhase: Equatable, Sendable {
    /// Nothing is cached yet and the first read has not finished.
    case loading
    /// The couple has not picked a play style and language yet.
    case needsSetup
    /// The couple's game does not exist yet and is being created.
    case preparing
    /// It is this person's turn to pick a word.
    case chooseWord
    /// The partner is picking a word.
    case waitingForWord
    /// This person is drawing the word they picked.
    case drawing
    /// The drawing is sent or queued. The partner is guessing.
    case waitingForGuess
    /// This person guesses, and the partner is still picking or drawing out of sight.
    case waitingForDrawing
    /// This person guesses while the partner draws, and watches the strokes appear.
    case watchingLive
    /// This person guesses on the finished drawing, with the replay.
    case guessing
    /// The round ended. Shows the word, the result, and the save prompt.
    case reveal
    /// This person's last move is queued on the phone, and the next turn can
    /// start once it reaches the server.
    case waitingToSync

    /// The guesser can type the answer with the tiles.
    var allowsGuessing: Bool {
        switch self {
        case .waitingForDrawing, .watchingLive, .guessing:
            true
        default:
            false
        }
    }
}

nonisolated struct DrawAndGuessResolution: Equatable, Sendable {
    let phase: DrawAndGuessPhase
    /// The round the phase is about, with unsent moves applied.
    let round: DrawAndGuessRoundView?
    /// A move is saved on this phone and not on the server yet.
    let isWaitingToSend: Bool
}

/// Works out the phase from the server's state, this phone's unsent moves, and
/// what the person has already seen. It reads no clock and no network.
nonisolated struct DrawAndGuessResolver: Sendable {
    let userID: UUID

    func resolve(
        state: RemoteDrawAndGuessState?,
        pending: DrawAndGuessPendingWork,
        acknowledgedRoundIDs: Set<UUID>,
        isPartnerDrawingLive: Bool
    ) -> DrawAndGuessResolution {
        guard let state else {
            return DrawAndGuessResolution(phase: .loading, round: nil, isWaitingToSend: pending.hasMoveWaiting)
        }
        let waiting = pending.hasMoveWaiting
        guard state.settings != nil else {
            return DrawAndGuessResolution(phase: .needsSetup, round: nil, isWaitingToSend: waiting)
        }
        guard let game = state.game else {
            return DrawAndGuessResolution(phase: .preparing, round: nil, isWaitingToSend: waiting)
        }

        let round = effectiveRound(state: state, game: game, pending: pending)
        if let round, !round.isFinished {
            // The partner may have solved the last round and started the next one while
            // this person was away. That result comes first.
            if let unseen = unseenResult(state: state, newerRoundID: round.id, acknowledged: acknowledgedRoundIDs) {
                return DrawAndGuessResolution(phase: .reveal, round: unseen, isWaitingToSend: waiting)
            }
            let phase = activePhase(round: round, isPartnerDrawingLive: isPartnerDrawingLive)
            return DrawAndGuessResolution(phase: phase, round: round, isWaitingToSend: waiting)
        }
        if let round, !acknowledgedRoundIDs.contains(round.id) {
            return DrawAndGuessResolution(phase: .reveal, round: round, isWaitingToSend: waiting)
        }

        return DrawAndGuessResolution(phase: phaseBetweenRounds(game), round: round, isWaitingToSend: waiting)
    }

    /// The latest finished round before `newerRoundID`, when this phone has not
    /// shown its result. Only the latest counts, so a fresh install shows one
    /// result and not the whole history.
    private func unseenResult(
        state: RemoteDrawAndGuessState,
        newerRoundID: UUID,
        acknowledged: Set<UUID>
    ) -> DrawAndGuessRoundView? {
        let rounds = (state.currentRound.map { [$0] } ?? []) + state.recentRounds
        guard let latest = rounds.first(where: { $0.id != newerRoundID && $0.state.isFinished }),
              !acknowledged.contains(latest.id)
        else {
            return nil
        }
        return DrawAndGuessRoundView(latest)
    }

    private func phaseBetweenRounds(_ game: RemoteDrawAndGuessGame) -> DrawAndGuessPhase {
        switch game.state {
        case .choosingWord:
            game.turnUserID == userID ? .chooseWord : .waitingForWord
        case .drawing, .guessing:
            // The round ended on this phone and the server has not heard yet.
            .waitingToSync
        }
    }

    private func activePhase(round: DrawAndGuessRoundView, isPartnerDrawingLive: Bool) -> DrawAndGuessPhase {
        if round.isDrawer(userID) {
            return round.isDrawingSent ? .waitingForGuess : .drawing
        }
        if round.isDrawingSent {
            return .guessing
        }
        return isPartnerDrawingLive ? .watchingLive : .waitingForDrawing
    }

    /// The server's current round, or the round a queued word pick starts, with
    /// the unsent drawing, guesses and give up applied.
    func effectiveRound(
        state: RemoteDrawAndGuessState,
        game: RemoteDrawAndGuessGame,
        pending: DrawAndGuessPendingWork
    ) -> DrawAndGuessRoundView? {
        guard var round = baseRound(state: state, game: game, pending: pending) else {
            return nil
        }
        if pending.hasDrawing(roundID: round.id) {
            round.isDrawingSent = true
            // A round the partner solved live still gets its drawing attached.
            if round.state == .drawing {
                round.state = .guessing
            }
        }
        if !round.isFinished {
            applyUnsentGuesses(to: &round, pending: pending)
        }
        return round
    }

    /// The round the server has, or the one a queued word pick starts.
    private func baseRound(
        state: RemoteDrawAndGuessState,
        game: RemoteDrawAndGuessGame,
        pending: DrawAndGuessPendingWork
    ) -> DrawAndGuessRoundView? {
        if let pick = pending.pick,
           pick.gameID == game.id,
           state.currentRound?.id != pick.roundID,
           let partnerID = state.partnerUserID {
            return DrawAndGuessRoundView(
                pick: pick,
                number: game.turnNumber,
                drawerUserID: userID,
                guesserUserID: partnerID
            )
        }
        return state.currentRound.map(DrawAndGuessRoundView.init)
    }

    private func applyUnsentGuesses(to round: inout DrawAndGuessRoundView, pending: DrawAndGuessPendingWork) {
        let guesses = pending.guesses(roundID: round.id)
        for guess in guesses {
            round.attempts.append(
                DrawAndGuessAttemptView(
                    id: guess.id,
                    userID: userID,
                    text: guess.guess.lowercased(),
                    isCorrect: guess.isCorrect,
                    createdAt: guess.createdAt,
                    isPending: true
                )
            )
        }
        if let solved = guesses.first(where: \.isCorrect) {
            round.state = .solved
            round.localSolvedAt = solved.createdAt
        } else if pending.hasGiveUp(roundID: round.id) {
            round.state = .missed
        }
    }
}
