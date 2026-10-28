import Foundation

/// Where the person is in the game right now. Each case is one screen state.
nonisolated enum MindMeldPhase: Equatable, Sendable {
    /// Nothing is cached yet and the first read has not finished.
    case loading
    /// The couple has no game in play, or one is being started. The view model
    /// starts the first game.
    case starting
    /// The open round needs this person's word.
    case write
    /// This person's word is locked in and the partner's is not. `isQueued` is
    /// true while the word is only saved on this phone.
    case waiting(isQueued: Bool)
    /// A round or a game ending this person has not seen yet. Also the open round
    /// while this person's word is on its way to a partner who already locked in.
    /// The cards stay face down until the round comes back revealed.
    case reveal
    /// A finished game whose ending this person has seen. Shows its last round, settled.
    case over
}

/// This phone's unsent moves, and what this person has already seen.
nonisolated struct MindMeldPendingWork: Equatable, Sendable {
    /// Round id to the word locked in on this phone and not yet on the server.
    var lockedWords: [UUID: String] = [:]
    /// Near misses this person counted on this phone.
    var countedRounds: Set<UUID> = []
    /// Rounds whose reveal this person has seen, with a mark not yet on the server.
    var seenReveals: Set<UUID> = []
    /// Games whose ending this person has seen, with a mark not yet on the server.
    var seenEnds: Set<UUID> = []
    /// The last send failed while the phone had a connection. The view model
    /// reads this. The resolver does not.
    var lastSendFailedWhileOnline = false
    /// A waiting lock-in or count has had a try that did not get through, for any
    /// reason. Until then it is on its first send, and the screen says nothing
    /// about it being on this phone, so a normal send never flashes that line.
    /// The resolver reads it to choose between the reveal and waiting when the
    /// partner's word is already in.
    var hasFailedMoveAttempt = false
    /// A game is being started or restarted.
    var isStarting = false

    static let none = Self()
}

/// One revealed round, as the trail shows it.
nonisolated struct MindMeldTrailRound: Equatable, Identifiable, Sendable {
    let id: UUID
    let roundNumber: Int
    let mine: String
    let theirs: String
    let outcome: MindMeldRevealOutcome
    /// A partner counted the near miss as a match.
    let isCounted: Bool
}

nonisolated struct MindMeldResolution: Equatable, Sendable {
    var phase: MindMeldPhase
    /// The game the phase is about, with unsent moves applied. For a reveal of
    /// an ending the person missed, this is the earlier game.
    var game: RemoteMindMeldGame?
    /// The open round for `write` and `waiting`. The last revealed round for
    /// `reveal` and `over`.
    var round: RemoteMindMeldRound?
    /// A partner started over and ended the game this person was in. The view
    /// shows a one-time note and marks this game's ending as seen. It stops
    /// reporting once that mark is queued, so the view model keeps the note.
    var partnerRestartedGameID: UUID?
}

/// Works out the phase from the server's state and this phone's unsent moves.
/// It reads no clock and no network. A reveal counts as seen when the server has
/// this person's seen time for it, or a mark for it waits on this phone. The
/// same goes for the ending of a game.
nonisolated struct MindMeldResolver: Sendable {
    let userID: UUID

    /// `hasLoaded` is true once a read has finished. With a finished read and no
    /// state, the couple has no game yet.
    func resolve(
        state: RemoteMindMeldState?,
        hasLoaded: Bool,
        pending: MindMeldPendingWork
    ) -> MindMeldResolution {
        guard let state else {
            return MindMeldResolution(phase: hasLoaded ? .starting : .loading)
        }
        if pending.isStarting {
            return MindMeldResolution(phase: .starting)
        }
        // A game the person has not seen the end of comes first, then the current one.
        var restartedGameID: UUID?
        if let previous = unseenPrevious(state, pending) {
            if previous.endReason != .restart, let last = previous.lastRevealedRound {
                return MindMeldResolution(phase: .reveal, game: previous, round: last)
            }
            restartedGameID = restartedByPartner(previous)
        }
        var resolution = state.current.map { resolveCurrent(apply(pending, to: $0), pending) }
            ?? MindMeldResolution(phase: .starting)
        resolution.partnerRestartedGameID = restartedGameID
        return resolution
    }

    /// A copy of the game with the unsent lock-ins and counts applied. A count
    /// turns the near miss into a meld, as the server does: the end reason goes and
    /// the round that was open after it is dropped.
    func apply(_ pending: MindMeldPendingWork, to game: RemoteMindMeldGame) -> RemoteMindMeldGame {
        var game = game
        for index in game.rounds.indices where game.rounds[index].state == .open && game.rounds[index].myWord == nil {
            game.rounds[index].myWord = pending.lockedWords[game.rounds[index].id]
        }
        if let round = game.countableRound, pending.countedRounds.contains(round.id),
           let index = game.rounds.firstIndex(where: { $0.id == round.id }) {
            game.rounds[index].countedByUserID = userID
            game.state = .melded
            game.endReason = nil
            game.rounds.removeSubrange((index + 1)...)
        }
        return game
    }

    private func unseenPrevious(_ state: RemoteMindMeldState, _ pending: MindMeldPendingWork) -> RemoteMindMeldGame? {
        guard let previous = state.previous, !hasSeenEnd(previous, pending) else { return nil }
        return apply(pending, to: previous)
    }

    private func restartedByPartner(_ game: RemoteMindMeldGame) -> UUID? {
        game.endReason == .restart && game.endedByUserID != userID ? game.id : nil
    }

    private func resolveCurrent(_ game: RemoteMindMeldGame, _ pending: MindMeldPendingWork) -> MindMeldResolution {
        if game.isFinished {
            return resolveFinished(game, pending)
        }
        if let last = game.lastRevealedRound, !hasSeenReveal(last, pending) {
            return MindMeldResolution(phase: .reveal, game: game, round: last)
        }
        // A game in play always has an open round. A stale state without one waits for the next.
        guard let open = game.openRound else {
            return MindMeldResolution(phase: .loading, game: game)
        }
        guard open.myWord != nil else {
            return MindMeldResolution(phase: .write, game: game, round: open)
        }
        // A word with no lock time only exists on this phone. When the partner's
        // word is in, the server reveals the round as it takes mine, so the reveal
        // opens now and plays when the round comes back revealed. A send that did
        // not get through waits instead, where the screen says the word is on the phone.
        let isQueued = open.myLockedAt == nil
        if isQueued, open.partnerLocked, !pending.hasFailedMoveAttempt {
            return MindMeldResolution(phase: .reveal, game: game, round: open)
        }
        return MindMeldResolution(phase: .waiting(isQueued: isQueued), game: game, round: open)
    }

    private func resolveFinished(_ game: RemoteMindMeldGame, _ pending: MindMeldPendingWork) -> MindMeldResolution {
        // A game a restart ended has nothing to show. The next game starts.
        guard game.endReason != .restart, let last = game.lastRevealedRound else {
            return MindMeldResolution(phase: .starting)
        }
        return MindMeldResolution(phase: hasSeenEnd(game, pending) ? .over : .reveal, game: game, round: last)
    }

    private func hasSeenEnd(_ game: RemoteMindMeldGame, _ pending: MindMeldPendingWork) -> Bool {
        game.myEndSeenAt != nil || pending.seenEnds.contains(game.id)
    }

    private func hasSeenReveal(_ round: RemoteMindMeldRound, _ pending: MindMeldPendingWork) -> Bool {
        round.myRevealSeenAt != nil || pending.seenReveals.contains(round.id)
    }
}

// MARK: - What the screens read

nonisolated extension RemoteMindMeldGame {
    /// The round a partner can still count: the last revealed round of a game
    /// that is in play or ended after round 10, when it is an uncounted near miss.
    var countableRound: RemoteMindMeldRound? {
        guard state != .melded, endReason != .restart, let round = lastRevealedRound,
              round.outcome == .near, round.countedByUserID == nil else { return nil }
        return round
    }

    /// How a revealed round reads, or nil for an open one. A near miss stays
    /// `.near` in the last round too, because it can still be counted.
    func displayOutcome(of round: RemoteMindMeldRound) -> MindMeldRevealOutcome? {
        guard round.state == .revealed, let outcome = round.outcome else { return nil }
        if outcome == .match || round.countedByUserID != nil {
            return .meld
        }
        if outcome == .near {
            return .near
        }
        let isFinalRound = state == .ended && endReason == .rounds && round.roundNumber >= maxRounds
        return isFinalRound ? .gotAway : .miss
    }
}

nonisolated extension MindMeldResolution {
    var partnerRestartedNote: Bool { partnerRestartedGameID != nil }

    /// The partner locked in and this person has not, or a reveal waits. A round
    /// nobody has locked in is nobody's turn.
    var isYourTurn: Bool {
        switch phase {
        case .reveal: true
        case .write: round?.partnerLocked == true
        default: false
        }
    }

    var roundNumber: Int { round?.roundNumber ?? 1 }

    /// How `round` reads, when it is revealed.
    var displayOutcome: MindMeldRevealOutcome? {
        round.flatMap { game?.displayOutcome(of: $0) }
    }

    /// "Count it" is on offer for `round`.
    var canCount: Bool {
        round != nil && game?.countableRound?.id == round?.id
    }

    /// The words of the last revealed round, mine first. The write title names them.
    var connectingPair: (mine: String, theirs: String)? {
        guard let last = game?.lastRevealedRound, let mine = last.myWord, let theirs = last.partnerWord else {
            return nil
        }
        return (mine, theirs)
    }

    /// The round of `connectingPair`.
    var connectingRoundID: UUID? {
        game?.lastRevealedRound?.id
    }

    /// Every revealed round of the game, oldest first.
    var trail: [MindMeldTrailRound] {
        guard let game else { return [] }
        return game.rounds.compactMap { round in
            guard let outcome = game.displayOutcome(of: round), let mine = round.myWord,
                  let theirs = round.partnerWord else { return nil }
            return MindMeldTrailRound(
                id: round.id,
                roundNumber: round.roundNumber,
                mine: mine,
                theirs: theirs,
                outcome: outcome,
                isCounted: round.countedByUserID != nil
            )
        }
    }
}

nonisolated extension MindMeldResolver {
    /// It is this person's turn once the partner has locked in a word for the open round
    /// and they have not. It reads the current game and not the phase, so the turn also
    /// arrives while the last round's reveal is still on screen.
    func attention(state: RemoteMindMeldState?, pending: MindMeldPendingWork) -> GameAttention {
        guard let current = state?.current else { return GameAttention() }
        let game = apply(pending, to: current)
        guard !game.isFinished, let open = game.openRound, open.partnerLocked, open.myWord == nil else {
            return GameAttention()
        }
        return GameAttention(turn: "round \(open.id) partner locked")
    }
}
