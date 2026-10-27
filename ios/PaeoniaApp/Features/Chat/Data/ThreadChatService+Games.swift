import Foundation

extension ThreadChatService {
    nonisolated func liveGameUpdates(ownerUserID: UUID, coupleID: UUID, source: GameConversationSource) -> AsyncStream<
        Void
    > {
        let updates = gateway.liveGameResults(coupleID: coupleID, source: source)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                let generation = await cache.purgeGeneration()
                for await result in updates {
                    guard !Task.isCancelled else { break }
                    guard
                        await cache.saveGameResult(
                            result, ownerUserID: ownerUserID, subjectID: source.id, unlessPurgedSince: generation)
                    else { break }
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
        let result = try await gateway.loadGameResult(coupleID: coupleID, source: source)
        guard
            await cache.saveGameResult(
                result, ownerUserID: ownerUserID, subjectID: source.id, unlessPurgedSince: generation)
        else {
            throw CancellationError()
        }
        LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
        return result
    }
}
