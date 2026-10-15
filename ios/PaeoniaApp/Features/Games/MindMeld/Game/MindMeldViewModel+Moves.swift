import Foundation

// The moves of a game. Each one is written to the pending operations first and
// sent in the background, so it works offline. The screen reacts to the saved
// move at once through `recompute()`.
extension MindMeldViewModel {
    // MARK: - Writing

    /// Locks in the word in the field. Returns false when the field is empty or
    /// the word breaks a rule, so the screen can tell the person. Returns true
    /// when the word is locked in. It is saved on the phone and sent when the
    /// phone is online.
    @discardableResult
    func lockIn() -> Bool {
        guard phase == .write, let game, let round = openRound, unsavedLocks[round.id] == nil else { return false }
        let word = MindMeldWord.normalized(draft)
        guard !word.isEmpty, MindMeldWord.validate(word, used: usedWords) == nil else { return false }
        let payload = MindMeldLockPayload(roundID: round.id, gameID: game.id, word: word, createdAt: dependencies.now())
        let operation = dependencies.operationProvider.makeOperation()

        // The lock-in shows at once, also before the queue has it.
        unsavedLocks[round.id] = word
        showsPartnerRestartedNote = false
        draft = ""
        recompute()
        queueMove { [self] in
            let saved = await enqueue(
                .lockMindMeldWord,
                scope: "mind-meld-lock:\(round.id.uuidString.lowercased())",
                payload: payload,
                operation: operation
            )
            unsavedLocks[round.id] = nil
            if !saved, draft.isEmpty, openRound?.id == round.id {
                // Nothing the person typed is lost: the word goes back in the field.
                draft = word
            }
            recompute()
        }
        return true
    }

    /// Fills the field with a random starter word in the couple's game language,
    /// one that nobody used in this game and that is not the word already there.
    func surpriseMe() {
        guard phase == .write else { return }
        var excluded = Set(usedWords.keys)
        excluded.insert(MindMeldWord.matchKey(draft))
        var generator = SystemRandomNumberGenerator()
        draft = MindMeldStarterWords.random(
            for: overview?.settings?.language ?? .en,
            excluding: excluded,
            using: &generator
        )
    }

    // MARK: - Reveal

    /// "Count it": counts the near miss as a match. Both partners win together,
    /// so nobody has to agree first.
    func countIt() {
        guard resolution.canCount, let round = resolution.round else { return }
        let payload = MindMeldCountPayload(roundID: round.id, createdAt: dependencies.now())
        let operation = dependencies.operationProvider.makeOperation()
        queueMove { [self] in
            _ = await enqueue(
                .countMindMeldRound,
                scope: "mind-meld-count:\(round.id.uuidString.lowercased())",
                payload: payload,
                operation: operation
            )
        }
    }

    /// The reveal reached its verdict on screen. Leaving the screen after that
    /// counts as having seen it.
    func revealSettled() {
        settledRevealRoundID = resolution.round?.id
    }

    /// The person is done with the reveal: "Next round", or leaving the screen.
    /// Marks the reveal as seen, and the ending too when the game is finished. A
    /// finished game stays on its last round until "Play again".
    func continueFromReveal() {
        guard phase == .reveal, let game, let round else { return }
        queueMove { [self] in
            await queueSeenMarks(of: game, round: round)
        }
    }

    /// Saves the seen marks the reveal still needs. A mark is not saved twice.
    private func queueSeenMarks(of game: RemoteMindMeldGame, round: RemoteMindMeldRound) async {
        if round.myRevealSeenAt == nil, !pending.seenReveals.contains(round.id) {
            await enqueue(
                .markMindMeldRevealSeen,
                scope: "mind-meld-reveal-seen:\(round.id.uuidString.lowercased())",
                payload: MindMeldRevealSeenPayload(roundID: round.id, createdAt: dependencies.now())
            )
        }
        if game.isFinished, game.myEndSeenAt == nil, !pending.seenEnds.contains(game.id) {
            await enqueue(
                .markMindMeldEndSeen,
                scope: "mind-meld-end-seen:\(game.id.uuidString.lowercased())",
                payload: MindMeldEndSeenPayload(gameID: game.id, createdAt: dependencies.now())
            )
        }
    }

    // MARK: - Starting over

    /// "Play again" on a finished game: marks the reveal and the ending as seen,
    /// then starts a new game. The first partner to tap starts it, and the other
    /// joins the same game. Needs a connection, like creating any game.
    func playAgain() async {
        guard !isStartingGame, let game, game.isFinished, let round else { return }
        await queueSeenMarks(of: game, round: round)
        // A "Count it" still on this phone melds the game only when it reaches the
        // server. Until then the server still plays this game and would hand it back.
        let hasQueuedCount = { game.rounds.contains { self.pending.countedRounds.contains($0.id) } }
        if hasQueuedCount() {
            await syncAfterLocalChange?()
            await reload()
            if hasQueuedCount() {
                // The sync failed for a reason this screen doesn't know, so the
                // banner doesn't guess that the connection is to blame.
                notice = .couldNotStartGame(.other)
                return
            }
        }
        await runStarting(isAutomatic: false) {
            _ = try await self.gateway.startMindMeldGame()
        }
    }

    /// "Start over" in a game in play, after the confirm alert. Ends the game and
    /// starts a new one at round 1. Needs a connection.
    func restart() async {
        // Also from a reveal: the toolbar offers it whenever the game is in play.
        guard !isStartingGame, let game, game.state == .playing else { return }
        await runStarting(isAutomatic: false) {
            _ = try await self.gateway.restartMindMeld(gameID: game.id)
        }
    }

    // MARK: - Queueing

    /// Runs `work` after the moves queued before it.
    func queueMove(_ work: @escaping @MainActor () async -> Void) {
        moveTask = Task { [previous = moveTask] in
            await previous?.value
            await work()
        }
    }

    /// Saves a move in the pending operations, shows its effect, and nudges the
    /// sync to send it now. Returns false when it could not be saved.
    @discardableResult
    func enqueue(
        _ kind: SyncPendingOperationKind,
        scope: String,
        payload: some Encodable,
        operation: SyncClientOperation? = nil
    ) async -> Bool {
        guard let userID = currentUserID, let data = try? JSONEncoder().encode(payload) else { return false }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: operation ?? dependencies.operationProvider.makeOperation(),
                    operationKind: kind,
                    idempotencyScope: scope,
                    requestData: data
                )
            )
        } catch {
            notice = .couldNotSaveMove
            return false
        }
        await reload()
        if let sync = syncAfterLocalChange {
            Task { await sync() }
        }
        return true
    }
}
