import PencilKit
import SwiftUI

// The moves of a turn. Each one is written to the pending operations first and
// sent in the background, so it works offline. The screen reacts to the saved
// move at once through `recompute()`.
extension DrawAndGuessViewModel {
    // MARK: - Picking a word

    func chooseWord(_ choice: DrawAndGuessWordChoice) async {
        guard phase == .chooseWord else { return }
        await enqueuePick(
            choice: choice.difficulty,
            word: choice.word,
            wordID: choice.wordID,
            points: choice.points
        )
    }

    /// Starts the round with the typed "Draw your own" word, when it is valid.
    func chooseCustomWord() async {
        guard phase == .chooseWord, let word = customWordValidation.word else { return }
        await enqueuePick(choice: .custom, word: word, wordID: nil, points: Self.customWordPoints)
        customWord = ""
    }

    /// A custom word is worth the same as a medium word.
    static let customWordPoints = 2

    private func enqueuePick(
        choice: DrawAndGuessDifficulty,
        word: String,
        wordID: String?,
        points: Int
    ) async {
        guard let game = state?.game else { return }
        let payload = GamePickWordPayload(
            gameID: game.id,
            roundID: UUID(),
            choice: choice,
            word: word,
            wordID: wordID,
            points: points,
            createdAt: dependencies.now()
        )
        await enqueue(.pickDrawWord, scope: "game-pick:\(game.id.uuidString.lowercased())", payload: payload)
    }

    // MARK: - Drawing

    /// Whether the Done button works.
    var canFinishDrawing: Bool {
        phase == .drawing && !board.isEmpty && board.canvasSide > 0
    }

    /// Sends the drawing. It is saved on the phone first and goes out when the
    /// phone is online.
    func finishDrawing() async {
        guard canFinishDrawing, let round else { return }
        // A late eraser change is read from the canvas first, so it goes out too.
        board.refreshDrawingFromCanvas()
        await queueDrawing(for: round, drawing: board.canonicalDrawing)
    }

    func queueDrawing(for round: DrawAndGuessRoundView, drawing: PKDrawing) async {
        guard let userID = currentUserID, let coupleID = participants.coupleID,
              let gameID = state?.game?.id
        else { return }
        let data = drawing.dataRepresentation()
        guard WidgetDrawingLimits.allows(
            byteCount: data.count,
            strokeCount: drawing.strokes.count,
            pointCount: drawing.paeoniaPointCount
        ) else {
            notice = .drawingTooBig
            return
        }
        let payload = GameSubmitDrawingPayload(
            gameID: gameID,
            roundID: round.id,
            coupleID: coupleID,
            drawingData: data,
            reserveOperation: dependencies.operationProvider.makeOperation(),
            finalizeOperation: dependencies.operationProvider.makeOperation()
        )
        let scope = "game-drawing:\(round.id.uuidString.lowercased())"
        if await enqueue(.submitGameDrawing, scope: scope, payload: payload) {
            // The queued move carries the drawing now.
            dependencies.drawingStore.removeDraft(ownerUserID: userID, roundID: round.id)
        }
    }

    /// The partner solved the round while this person was still drawing, or the
    /// round ended while they were away from it. The drawing goes out as it is,
    /// so the reveal and Memories have it. It comes from the canvas when the
    /// canvas holds the round, with a stroke in progress finished first, and
    /// otherwise from the draft saved on the phone.
    func sendLiveDrawingIfSolved() {
        guard let userID = currentUserID, let round, round.isFinished, round.isDrawer(userID),
              !round.isDrawingSent, !autoSentRoundIDs.contains(round.id)
        else { return }
        let isOnBoard = boardRoundID == round.id && !board.isEmpty && board.canvasSide > 0
        let draft = isOnBoard ? nil : dependencies.drawingStore.draft(ownerUserID: userID, roundID: round.id)
            .flatMap { try? PKDrawing(data: $0) }
            .flatMap { $0.strokes.isEmpty ? nil : $0 }
        guard isOnBoard || draft != nil else { return }
        autoSentRoundIDs.insert(round.id)
        let board = board
        Task {
            let drawing: PKDrawing
            if let draft {
                drawing = draft
            } else {
                drawing = await board.finishedCanonicalDrawing()
            }
            await queueDrawing(for: round, drawing: drawing)
        }
    }

    func drawingChangedByUser(_ drawing: PKDrawing) {
        live?.localDrawingDidChange(drawing, side: board.canvasSide)
        draftTask?.cancel()
        draftTask = Task { [weak self, sleep] in
            try? await sleep(.seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveDraftNow()
        }
    }

    /// Keeps the unsent drawing on the phone, so closing the app loses nothing.
    func saveDraftNow() {
        guard let userID = currentUserID, phase == .drawing, let round, boardRoundID == round.id else { return }
        if board.isEmpty || board.canvasSide <= 0 {
            if board.isEmpty {
                dependencies.drawingStore.removeDraft(ownerUserID: userID, roundID: round.id)
            }
            return
        }
        dependencies.drawingStore.saveDraft(
            board.canonicalDrawing.dataRepresentation(),
            ownerUserID: userID,
            roundID: round.id
        )
    }

    // MARK: - Guessing

    func placeTile(_ tile: DrawAndGuessTile) {
        guard phase.allowsGuessing, !isShowingWrongGuess, slots.place(tile) else { return }
        if slots.isFull {
            submitFullGuess()
        }
    }

    /// Takes a letter back out of its slot.
    func removeTile(atSlot index: Int) {
        guard phase.allowsGuessing, !isShowingWrongGuess, slots.status != .correct else { return }
        slots.remove(at: index)
    }

    func clearGuess() {
        guard !isShowingWrongGuess else { return }
        slots.clear()
    }

    private func submitFullGuess() {
        guard let round else { return }
        let guess = slots.filledWord
        let isCorrect = slots.status == .correct
        if isCorrect {
            queuingCorrectGuessRoundID = round.id
            solvedCount += 1
            keepLiveSnapshot(of: round.id)
        } else {
            wrongGuessCount += 1
            isShowingWrongGuess = true
            wrongGuessTask?.cancel()
            wrongGuessTask = Task { [weak self, sleep] in
                await self?.returnWrongGuess(sleep: sleep)
            }
        }
        let now = dependencies.now()
        let claim = isCorrect ? speedBonusClaim(at: now) : nil
        let payload = GameGuessPayload(
            id: UUID(),
            roundID: round.id,
            guess: guess.lowercased(),
            isCorrect: isCorrect,
            createdAt: now,
            speedBonus: claim?.speedBonus,
            solveMs: claim?.solveMs
        )
        Task {
            await enqueue(.submitGameGuess, scope: "game-guess:\(round.id.uuidString.lowercased())", payload: payload)
            if isCorrect, queuingCorrectGuessRoundID == round.id {
                queuingCorrectGuessRoundID = nil
                // A guess that could not be saved leaves the round open.
                unlockRefusedCorrectGuess()
            }
        }
    }

    /// The live room clears when the drawer leaves. Keeps what was drawn, on
    /// disk too, so a relaunch before the sent drawing arrives still shows it
    /// on the reveal.
    private func keepLiveSnapshot(of roundID: UUID) {
        guard let userID = currentUserID, let snapshot = live?.partnerCanvasDrawing, !snapshot.strokes.isEmpty
        else { return }
        liveSnapshots[roundID] = snapshot
        dependencies.drawingStore.saveLiveSnapshot(snapshot.dataRepresentation(), ownerUserID: userID, roundID: roundID)
    }

    /// How long the wrong word stays in the slots while they shake.
    static let wrongGuessHold: Duration = .milliseconds(400)
    /// The hold with Reduce Motion, which has no shake.
    static let wrongGuessHoldReducedMotion: Duration = .milliseconds(600)
    /// The tiles fly back one at a time, the last letter first.
    static let tileReturnGap: Duration = .milliseconds(30)

    private func returnWrongGuess(sleep: @Sendable (Duration) async throws -> Void) async {
        try? await sleep(prefersReducedMotion ? Self.wrongGuessHoldReducedMotion : Self.wrongGuessHold)
        guard !Task.isCancelled else { return }
        if prefersReducedMotion {
            slots.clear()
        } else {
            for slot in slots.slots.reversed() where slot.tile != nil {
                slots.remove(at: slot.id)
                try? await sleep(Self.tileReturnGap)
                guard !Task.isCancelled else { return }
            }
        }
        isShowingWrongGuess = false
    }

    /// "Show me": the round counts as missed and the answer shows.
    func giveUp() async {
        guard phase.allowsGuessing, let round else { return }
        let payload = GameGiveUpPayload(roundID: round.id, createdAt: dependencies.now())
        await enqueue(.giveUpGameRound, scope: "game-giveup:\(round.id.uuidString.lowercased())", payload: payload)
    }

    // MARK: - Queueing

    /// "Try again" on the waiting screen: sends what waits now, then reads the
    /// server's state.
    func retrySending() async {
        await syncAfterLocalChange?()
        await refresh()
    }

    /// Saves a move in the pending operations, shows its effect, and nudges the
    /// sync to send it now.
    @discardableResult
    func enqueue(
        _ kind: SyncPendingOperationKind,
        scope: String,
        payload: some Encodable
    ) async -> Bool {
        guard let userID = currentUserID, let data = try? JSONEncoder().encode(payload) else { return false }
        do {
            try await dependencies.pendingOperationStore.enqueue(
                PendingSyncOperationRequest(
                    ownerUserID: userID,
                    operation: dependencies.operationProvider.makeOperation(),
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
