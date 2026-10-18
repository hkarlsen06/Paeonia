import Foundation

// The moves. Each one is written to the pending operations first and sent in the
// background, so it works offline. The screen reacts at once through `recompute()`.
extension ConsensioViewModel {
    // MARK: - Choosing a topic

    func select(_ choice: ConsensioTopicChoice) {
        selectedChoice = choice
        isWritingOwn = false
    }

    func openOwnTopic() {
        selectedChoice = nil
        isWritingOwn = true
    }

    func closeOwnTopic() {
        isWritingOwn = false
    }

    /// "Start": opens the line for the chosen topic. Nothing is sent yet, because
    /// the topic and the spot go to the server together.
    @discardableResult
    func startPlacing() -> Bool {
        guard phase == .choose, canStart else { return false }
        if isWritingOwn {
            placingTopic = .own(
                subject: ConsensioRules.normalized(ownSubject),
                leftEnd: ConsensioRules.normalized(ownLeftEnd),
                rightEnd: ConsensioRules.normalized(ownRightEnd)
            )
        } else {
            placingTopic = selectedChoice
        }
        marker = nil
        return true
    }

    /// Back from the line to the topic list, without sending anything.
    func cancelPlacing() {
        placingTopic = nil
        marker = nil
    }

    // MARK: - The marker

    /// The finger moved the marker. While guessing, the placer sees it move.
    func moveMarker(to position: Int, isTouching: Bool) {
        let clamped = min(max(position, 0), ConsensioRules.maxSpot)
        if marker != clamped {
            marker = clamped
        }
        isTouchingMarker = isTouching
        sendLiveMarker()
    }

    // MARK: - Placing

    /// "Lock it in". Returns false when there is nothing to place.
    @discardableResult
    func lockPlacement() -> Bool {
        guard phase == .choose, let topic = placingTopic, let spot = marker else { return false }
        let newest = max(state?.currentRound?.roundNumber ?? 0, game?.roundCount ?? 0)
        let payload = ConsensioPlacePayload(
            roundID: UUID(),
            roundNumber: newest + 1,
            topic: topic,
            spot: spot,
            createdAt: dependencies.now()
        )
        let operation = dependencies.operationProvider.makeOperation()
        unsavedPlacements.append(payload)
        placingTopic = nil
        selectedChoice = nil
        isWritingOwn = false
        ownSubject = ""
        ownLeftEnd = ""
        ownRightEnd = ""
        marker = nil
        recompute()
        queueMove { [self] in
            let saved = await enqueue(
                .placeConsensioSpot,
                scope: "consensio-place:\(payload.roundID.uuidString.lowercased())",
                payload: payload,
                operation: operation
            )
            unsavedPlacements.removeAll { $0.roundID == payload.roundID }
            recompute()
            if !saved, phase == .choose {
                // Nothing is lost: the topic and the marker go back on the line.
                placingTopic = topic
                marker = spot
            }
        }
        return true
    }

    // MARK: - Guessing

    /// "Lock in my guess". The reveal opens at once and plays when the server
    /// answers with the real spot.
    @discardableResult
    func lockGuess() -> Bool {
        guard phase == .guess, let round, let guess = marker, unsavedGuesses[round.id] == nil else { return false }
        let payload = ConsensioGuessPayload(roundID: round.id, guess: guess, createdAt: dependencies.now())
        let operation = dependencies.operationProvider.makeOperation()
        unsavedGuesses[round.id] = guess
        isTouchingMarker = false
        sendLiveMarker(force: true)
        recompute()
        queueMove { [self] in
            let saved = await enqueue(
                .guessConsensioSpot,
                scope: "consensio-guess:\(round.id.uuidString.lowercased())",
                payload: payload,
                operation: operation
            )
            unsavedGuesses[round.id] = nil
            recompute()
            if !saved, phase == .guess {
                marker = guess
            }
        }
        return true
    }

    // MARK: - Reveal

    func revealSettled() {
        settledRevealRoundID = round?.id
    }

    /// "Your turn to place" or "Continue". A reveal that played is marked seen. A
    /// held reveal is only stepped past for this visit, so it still plays once
    /// the real spot is here.
    func continueFromReveal() {
        guard case let .reveal(isHeld) = phase, let round else { return }
        if isHeld {
            deferredReveals.insert(round.id)
            recompute()
            return
        }
        guard round.myRevealSeenAt == nil, !pending.seenReveals.contains(round.id) else { return }
        unsavedSeen.insert(round.id)
        recompute()
        let payload = ConsensioRevealSeenPayload(roundID: round.id, createdAt: dependencies.now())
        queueMove { [self] in
            await enqueue(
                .markConsensioRevealSeen,
                scope: "consensio-reveal-seen:\(round.id.uuidString.lowercased())",
                payload: payload
            )
            unsavedSeen.remove(round.id)
            recompute()
        }
    }

    /// "Try again" when a send failed on a working connection.
    func retrySend() async {
        await syncAfterLocalChange?()
        await reload()
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
