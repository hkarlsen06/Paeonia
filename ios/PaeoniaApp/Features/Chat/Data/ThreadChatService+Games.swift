import Foundation

extension ThreadChatService {
    nonisolated func liveGameResultUpdates(ownerUserID: UUID, coupleID: UUID, source: GameConversationSource)
        -> AsyncStream<Void>
    {
        let updates = gateway.liveGameResults(coupleID: coupleID, source: source)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                let generation = await cache.purgeGeneration()
                for await result in updates {
                    guard !Task.isCancelled else { break }
                    let previous = await cache.gameResult(ownerUserID: ownerUserID, subjectID: source.id)
                    guard await cache.saveGameResult(
                        result, ownerUserID: ownerUserID, subjectID: source.id,
                        unlessPurgedSince: generation) else { break }
                    if result == nil { await evictRemovedResultPhoto(previous) }
                    LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func keepGameResult(_ result: GameConversationResult, ownerUserID: UUID, source: GameConversationSource) async {
        let generation = await cache.purgeGeneration()
        await cache.saveGameResult(
            result, ownerUserID: ownerUserID, subjectID: source.id, unlessPurgedSince: generation)
    }

    func cachedGameResult(ownerUserID: UUID, source: GameConversationSource) async -> GameConversationResult? {
        await cache.gameResult(ownerUserID: ownerUserID, subjectID: source.id)
    }

    func refreshGameResult(ownerUserID: UUID, coupleID: UUID, source: GameConversationSource) async throws
        -> GameConversationResult?
    {
        let generation = await cache.purgeGeneration()
        let previous = await cachedGameResult(ownerUserID: ownerUserID, source: source)
        let result = try await gateway.loadGameResult(coupleID: coupleID, source: source)
        guard
            await cache.saveGameResult(
                result, ownerUserID: ownerUserID, subjectID: source.id, unlessPurgedSince: generation)
        else {
            throw CancellationError()
        }
        if result == nil { await evictRemovedResultPhoto(previous) }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
        return result
    }

    func discardRemovedGameResult(ownerUserID: UUID, source: GameConversationSource, generation: Int) async {
        let result = await cache.gameResult(ownerUserID: ownerUserID, subjectID: source.id)
        guard await cache.saveGameResult(nil, ownerUserID: ownerUserID, subjectID: source.id,
                                         unlessPurgedSince: generation) else { return }
        await evictRemovedResultPhoto(result)
    }

    private func evictRemovedResultPhoto(_ result: GameConversationResult?) async {
        if case let .guessMySpot(round)? = result {
            await MemoryMediaImageService.shared?.evict(mediaAssetIDs: [round.photoMediaAssetID])
        }
    }
}
