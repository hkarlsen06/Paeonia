import Foundation

// The moves. Each one is written to the pending operations first and sent in the
// background, so it works offline. The screen reacts at once through `recompute()`.
extension GuessMySpotViewModel {
    // MARK: - The check

    /// A tap on the check map: the photo's spot goes there.
    func movePin(to spot: GuessMySpotCoordinate) {
        guard showsCheck, GuessMySpotRules.isValid(spot), draft?.spot != spot else { return }
        draft?.spot = spot
        draft?.place = nil
        namePlaceSoon()
    }

    /// "Choose another photo": back to the picker. Nothing was sent. A refused send
    /// that was put back is replaced, so its photo goes.
    func clearDraft() {
        namingTask?.cancel()
        if let replaced = draft {
            Task { await forgetRefusal(of: replaced) }
        }
        draft = nil
    }

    /// Looks the place up once the pin has stayed put for a moment, so a few quick
    /// taps make one request.
    func namePlaceSoon() {
        namingTask?.cancel()
        guard let spot = draft?.spot else { return }
        let namer = dependencies.guessMySpotPlaceNamer
        namingTask = Task { [weak self, sleep] in
            try? await sleep(.milliseconds(600))
            guard !Task.isCancelled else { return }
            let place = await namer.place(for: spot)
            guard !Task.isCancelled, let self, draft?.spot == spot else { return }
            draft?.place = place
        }
    }

    // MARK: - Sending

    /// "Send to [Name]". Returns false when there is nothing to send.
    @discardableResult
    func send() -> Bool {
        guard phase == .send, let draft, let spot = draft.spot, let userID = currentUserID,
              let coupleID = state?.coupleID ?? participants.coupleID
        else { return false }
        do {
            try dependencies.guessMySpotPhotos.save(draft.photo.jpeg, ownerUserID: userID, roundID: draft.roundID)
        } catch {
            notice = .couldNotSaveMove
            return false
        }
        let payload = sendPayload(for: draft, spot: spot, coupleID: coupleID)
        let operation = dependencies.operationProvider.makeOperation()
        namingTask?.cancel()
        unsavedSends.append(payload)
        self.draft = nil
        recompute()
        queueMove { [self] in
            let saved = await enqueue(
                .guessMySpotSend,
                scope: "guess-my-spot-send:\(payload.roundID.uuidString.lowercased())",
                payload: payload,
                operation: operation
            )
            unsavedSends.removeAll { $0.roundID == payload.roundID }
            recompute()
            if saved {
                await forgetRefusal(of: draft)
            } else if phase == .send, self.draft == nil {
                // Nothing is lost: the photo and the pin go back on the check.
                self.draft = draft
            }
        }
        return true
    }

    /// The queued send for a draft, with its ids fixed so retries replay the same requests.
    private func sendPayload(
        for draft: GuessMySpotDraft,
        spot: GuessMySpotCoordinate,
        coupleID: UUID
    ) -> GuessMySpotSendPayload {
        let newest = max(state?.currentRound?.roundNumber ?? 0, game?.roundCount ?? 0)
        return GuessMySpotSendPayload(
            details: GuessMySpotSendDetails(
                roundID: draft.roundID,
                roundNumber: newest + 1,
                spot: spot,
                placeName: draft.place?.name,
                takenOn: draft.photo.takenOn,
                placeCity: draft.place?.city,
                placeCountryCode: draft.place?.countryCode
            ),
            coupleID: coupleID,
            width: draft.photo.width,
            height: draft.photo.height,
            reserveOperation: dependencies.operationProvider.makeOperation(),
            finalizeOperation: dependencies.operationProvider.makeOperation(),
            createdAt: dependencies.now()
        )
    }

    // MARK: - Guessing

    /// A tap on the guess map. The sender sees the pin land when they are here.
    func dropGuess(at spot: GuessMySpotCoordinate) {
        guard phase == .guess, GuessMySpotRules.isValid(spot) else { return }
        guessPin = spot
        sendLivePin()
    }

    /// "Lock in my guess". The reveal opens at once and plays when the server
    /// answers with the real spot.
    @discardableResult
    func lockGuess() -> Bool {
        guard phase == .guess, let round, let guess = guessPin, unsavedGuesses[round.id] == nil else { return false }
        let payload = GuessMySpotGuessPayload(roundID: round.id, guess: guess, createdAt: dependencies.now())
        let operation = dependencies.operationProvider.makeOperation()
        unsavedGuesses[round.id] = guess
        sendLivePin()
        recompute()
        queueMove { [self] in
            let saved = await enqueue(
                .guessMySpotGuess,
                scope: "guess-my-spot-guess:\(round.id.uuidString.lowercased())",
                payload: payload,
                operation: operation
            )
            unsavedGuesses[round.id] = nil
            recompute()
            if !saved, phase == .guess {
                guessPin = guess
            }
        }
        return true
    }

    // MARK: - Reveal

    func revealSettled() {
        settledRevealRoundID = round?.id
    }

    /// "Your turn to send one" or "Continue". A reveal that played is marked seen.
    /// A held reveal is only stepped past for this visit, so it still plays once
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
        let payload = GuessMySpotRevealSeenPayload(roundID: round.id, createdAt: dependencies.now())
        queueMove { [self] in
            await enqueue(
                .guessMySpotRevealSeen,
                scope: "guess-my-spot-reveal-seen:\(round.id.uuidString.lowercased())",
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
