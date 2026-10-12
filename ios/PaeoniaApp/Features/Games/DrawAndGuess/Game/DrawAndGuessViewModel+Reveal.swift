import Foundation

// The reveal and the save prompt.
extension DrawAndGuessViewModel {
    /// Leaves the reveal for the next turn. Continuing without saving means no,
    /// so an open save question is answered "not now" for this person.
    func continueFromReveal() async {
        guard phase == .reveal, let round, let userID = currentUserID else { return }
        await skipSaving()
        await dependencies.cache.acknowledgeRound(round.id, ownerUserID: userID)
        await reload()
    }

    /// Closes the save question for this person only.
    func skipSaving() async {
        guard savePrompt == .ask, let round else { return }
        // Hidden at once. The server records it for the next time this person opens the game.
        savePrompt = .hidden
        declinedSaveRoundIDs.insert(round.id)
        try? await gateway.respondSavePrompt(roundID: round.id)
    }

    /// Renders the drawing to an image and queues it for Memories.
    func saveToMemories() async {
        guard savePrompt == .ask, let round, let coupleID = participants.coupleID else { return }
        guard let final = finalDrawing, let image = DrawAndGuessImageRenderer.render(final.drawing) else {
            // The partner's drawing has not arrived yet.
            loadDrawingIfNeeded()
            notice = .drawingUnavailable
            return
        }
        let payload = GameSaveRoundPayload(
            roundID: round.id,
            coupleID: coupleID,
            memoryID: UUID(),
            memoryMediaID: UUID(),
            imageData: image,
            memoryDate: MemoryTimeline.localDateString(for: dependencies.now()),
            reserveOperation: dependencies.operationProvider.makeOperation(),
            finalizeOperation: dependencies.operationProvider.makeOperation()
        )
        await enqueue(
            .saveGameRoundToMemories,
            scope: "game-save:\(round.id.uuidString.lowercased())",
            payload: payload
        )
    }
}
