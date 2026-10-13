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

    /// Closes the save question for this person only. It never waits for the
    /// network, so "Continue" moves on at once on a slow connection. The answer
    /// is kept on the phone too, so it stays closed after a relaunch while the
    /// server has not heard it.
    func skipSaving() async {
        guard savePrompt == .ask, let round, let userID = currentUserID else { return }
        savePrompt = .hidden
        declinedSaveRoundIDs.insert(round.id)
        await dependencies.cache.declineSave(round.id, ownerUserID: userID)
        let gateway = gateway
        let roundID = round.id
        Task { try? await gateway.respondSavePrompt(roundID: roundID) }
    }

    /// Queues the save for Memories at once. The image is the drawer's final
    /// drawing. When it is already on this phone, it is rendered now. Otherwise
    /// the queued save renders it once the drawer's drawing is sent, so a live
    /// canvas that missed a stroke, or a canvas still being drawn on, never
    /// becomes the memory.
    func saveToMemories() async {
        guard savePrompt == .ask, let round, let coupleID = participants.coupleID else { return }
        let image = submittedDrawing.flatMap { DrawAndGuessImageRenderer.render($0.drawing) }
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
