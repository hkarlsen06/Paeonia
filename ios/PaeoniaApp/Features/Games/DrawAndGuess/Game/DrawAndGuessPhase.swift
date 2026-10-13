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
    /// The round ended. Shows the word and the result.
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

extension DrawAndGuessPhase {
    /// What this phone tells the partner's phone through the relay room.
    /// The drawer of a round that has not ended stays `drawing`, also after Done,
    /// so the guesser keeps the live canvas.
    static func liveRole(phase: DrawAndGuessPhase, isDrawerOfUnfinishedRound: Bool) -> WidgetLivePresence.Role {
        if isDrawerOfUnfinishedRound {
            return .drawing
        }
        switch phase {
        case .watchingLive, .waitingForDrawing, .guessing: return .watching
        case .chooseWord: return .choosing
        case .reveal: return .result
        default: return .present
        }
    }
}

nonisolated struct DrawAndGuessResolution: Equatable, Sendable {
    let phase: DrawAndGuessPhase
    /// The round the phase is about, with unsent moves applied.
    let round: DrawAndGuessRoundView?
    /// A move is saved on this phone and not on the server yet.
    let isWaitingToSend: Bool
    /// The phase once the person moves on from the reveal, or `phase` when there
    /// is no reveal. Whose turn the hub shows comes from this. It is never `.reveal`.
    let turnPhase: DrawAndGuessPhase

    init(
        phase: DrawAndGuessPhase,
        round: DrawAndGuessRoundView?,
        isWaitingToSend: Bool,
        turnPhase: DrawAndGuessPhase? = nil
    ) {
        self.phase = phase
        self.round = round
        self.isWaitingToSend = isWaitingToSend
        self.turnPhase = turnPhase ?? phase
    }
}

/// Works out the phase from the server's state and this phone's unsent moves.
/// A finished round's result counts as seen when the server has this person's
/// "result seen" time for it, or a mark for it waits on this phone. It reads no
/// clock and no network.
nonisolated struct DrawAndGuessResolver: Sendable {
    let userID: UUID

    func resolve(
        state: RemoteDrawAndGuessState?,
        pending: DrawAndGuessPendingWork,
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
            let phase = activePhase(round: round, isPartnerDrawingLive: isPartnerDrawingLive)
            // The partner may have solved the last round and started the next one while
            // this person was away. That result comes first.
            if let unseen = unseenResult(
                state: state,
                newerRoundID: round.id,
                pending: pending
            ) {
                return DrawAndGuessResolution(phase: .reveal, round: unseen, isWaitingToSend: waiting, turnPhase: phase)
            }
            return DrawAndGuessResolution(phase: phase, round: round, isWaitingToSend: waiting)
        }
        if let round, !hasSeenResult(of: round, pending: pending) {
            // The guesser of a finished round draws next, also before the server has heard.
            let next: DrawAndGuessPhase = round.guesserUserID == userID ? .chooseWord : .waitingForWord
            return DrawAndGuessResolution(phase: .reveal, round: round, isWaitingToSend: waiting, turnPhase: next)
        }

        return DrawAndGuessResolution(phase: phaseBetweenRounds(game), round: round, isWaitingToSend: waiting)
    }

    private func hasSeenResult(of round: DrawAndGuessRoundView, pending: DrawAndGuessPendingWork) -> Bool {
        round.hasSeenResult(userID) || pending.hasResultSeen(roundID: round.id)
    }

    /// The latest finished round before `newerRoundID`, when this person has not
    /// moved past its result. Only the latest counts, so a person who never saw
    /// several results sees one and not the whole history. A drawing still queued
    /// for it counts as sent, as on the current round, so the drawer's phone never
    /// sends it twice.
    private func unseenResult(
        state: RemoteDrawAndGuessState,
        newerRoundID: UUID,
        pending: DrawAndGuessPendingWork
    ) -> DrawAndGuessRoundView? {
        let rounds = (state.currentRound.map { [$0] } ?? []) + state.recentRounds
        guard let latest = rounds.first(where: { $0.id != newerRoundID && $0.state.isFinished }) else {
            return nil
        }
        var round = DrawAndGuessRoundView(latest)
        guard !hasSeenResult(of: round, pending: pending) else {
            return nil
        }
        if pending.hasDrawing(roundID: round.id) {
            round.isDrawingSent = true
        }
        applyUnsentReaction(to: &round, pending: pending)
        return round
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
        applyUnsentReaction(to: &round, pending: pending)
        return round
    }

    /// A reaction made on this phone shows at once, before the server has it.
    private func applyUnsentReaction(to round: inout DrawAndGuessRoundView, pending: DrawAndGuessPendingWork) {
        if round.isFinished, let reaction = pending.reaction(roundID: round.id) {
            round.guesserReaction = reaction
        }
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
            // What the phone promised, until the server's numbers replace it.
            round.hintsUsed = solved.hintsUsed ?? 0
            round.speedBonus = round.hintsUsed > 0 ? 0 : solved.speedBonus ?? 0
            let isFirstAttempt = round.attempts.first?.id == solved.id
            round.firstTryBonus = round.hintsUsed == 0 && isFirstAttempt ? 1 : 0
        } else if pending.hasGiveUp(roundID: round.id) {
            round.state = .missed
        }
    }
}
