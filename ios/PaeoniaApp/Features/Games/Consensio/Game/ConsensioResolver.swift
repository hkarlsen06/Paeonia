import Foundation

/// Where the person is in the game right now. Each case is one screen state.
nonisolated enum ConsensioPhase: Equatable, Sendable {
    /// Nothing is cached yet and the first read has not finished.
    case loading
    /// The couple has no game yet, or one is being made. The view model makes it.
    case starting
    /// This person picks a topic and places their marker.
    case choose
    /// The partner placed a marker and this person guesses where it is.
    case guess
    /// This person's marker waits for the partner's guess. `isQueued` is true
    /// while the placement is only saved on this phone.
    case waitingForGuess(isQueued: Bool)
    /// The partner is picking a topic and placing their marker.
    case waitingForTopic
    /// A guessed round whose reveal this person has not seen. `isHeld` is true
    /// while this person's guess is on its way and the real spot is not here yet.
    case reveal(isHeld: Bool)
}

nonisolated struct ConsensioResolution: Equatable, Sendable {
    var phase: ConsensioPhase
    /// The round of `guess`, `waitingForGuess` and `reveal`, with this phone's unsent moves applied.
    var round: RemoteConsensioRound?
}

/// Works out the phase from the server's state and this phone's unsent moves.
/// It reads no clock and no network. A reveal counts as seen when the server has
/// this person's seen time for it, or a mark for it waits on this phone.
nonisolated struct ConsensioResolver: Sendable {
    let userID: UUID

    /// `hasLoaded` is true once a read has finished. `deferredReveals` are reveals
    /// this person stepped past while they were held, for this visit only.
    func resolve(
        state: RemoteConsensioState?,
        hasLoaded: Bool,
        isStarting: Bool,
        pending: ConsensioPendingWork,
        deferredReveals: Set<UUID> = []
    ) -> ConsensioResolution {
        guard let state else {
            return ConsensioResolution(phase: hasLoaded ? .starting : .loading)
        }
        guard let game = state.game, !isStarting else {
            return ConsensioResolution(phase: .starting)
        }
        let rounds = apply(pending, to: state)
        if let unseen = rounds.first(where: { isUnseenReveal($0, pending, deferredReveals) }) {
            return ConsensioResolution(phase: .reveal(isHeld: unseen.spot == nil), round: unseen)
        }
        guard let newest = rounds.last else {
            return ConsensioResolution(phase: game.turnUserID == userID ? .choose : .waitingForTopic)
        }
        if newest.guess == nil {
            if newest.placerUserID == userID {
                let isQueued = pending.placements.contains { $0.roundID == newest.id }
                return ConsensioResolution(phase: .waitingForGuess(isQueued: isQueued), round: newest)
            }
            return ConsensioResolution(phase: .guess, round: newest)
        }
        // The guesser of the newest round places the next one.
        return ConsensioResolution(phase: newest.guesserUserID == userID ? .choose : .waitingForTopic)
    }

    /// The two newest rounds, oldest first, with the unsent guesses and placements applied.
    func apply(_ pending: ConsensioPendingWork, to state: RemoteConsensioState) -> [RemoteConsensioRound] {
        var rounds = [state.previousRound, state.currentRound].compactMap(\.self)
        for index in rounds.indices where rounds[index].guess == nil {
            if let guess = pending.guesses[rounds[index].id], rounds[index].guesserUserID == userID {
                rounds[index].guess = guess
            }
        }
        for placement in pending.placements where !rounds.contains(where: { $0.id == placement.roundID }) {
            // A placement only follows a round this person guessed, or starts the game,
            // and only for the next round. One left from a turn that moved on shows nowhere.
            let next = max(rounds.last?.roundNumber ?? 0, state.game?.roundCount ?? 0) + 1
            let isMyTurn = rounds.last.map { $0.guess != nil && $0.guesserUserID == userID }
                ?? (state.game?.turnUserID == userID)
            guard isMyTurn, placement.roundNumber == next else { continue }
            rounds.append(queuedRound(placement, state: state))
        }
        return rounds
    }

    private func queuedRound(_ placement: ConsensioPlacePayload, state: RemoteConsensioState) -> RemoteConsensioRound {
        var topicID: String?
        var language: GameLanguage?
        if case let .catalog(topic) = placement.topic {
            topicID = topic.topicID
            language = topic.language
        }
        return RemoteConsensioRound(
            id: placement.roundID,
            roundNumber: placement.roundNumber,
            placerUserID: userID,
            guesserUserID: state.partnerUserID ?? userID,
            topicID: topicID,
            language: language,
            subject: placement.topic.subject,
            leftEnd: placement.topic.leftEnd,
            rightEnd: placement.topic.rightEnd,
            spot: placement.spot,
            placedAt: placement.createdAt
        )
    }

    private func isUnseenReveal(
        _ round: RemoteConsensioRound,
        _ pending: ConsensioPendingWork,
        _ deferred: Set<UUID>
    ) -> Bool {
        round.guess != nil
            && (round.placerUserID == userID || round.guesserUserID == userID)
            && round.myRevealSeenAt == nil
            && !pending.seenReveals.contains(round.id)
            && !deferred.contains(round.id)
    }
}

nonisolated extension ConsensioResolution {
    /// A topic to place, a guess, or a reveal waits for this person.
    var isYourTurn: Bool {
        switch phase {
        case .choose, .guess, .reveal: true
        default: false
        }
    }
}

nonisolated extension RemoteConsensioRound {
    /// The distance once both the guess and the spot are known.
    var knownDistance: Int? {
        distance ?? spot.flatMap { spot in guess.map { abs($0 - spot) } }
    }

    var knownPoints: Int? {
        points ?? knownDistance.map(ConsensioRules.points(distance:))
    }
}
