import Foundation

extension ThreadChatService {
    func cachedGameTimeline(ownerUserID: UUID, subject: GameChatSubject) async -> GameChatTimeline? {
        await cache.gameTimeline(ownerUserID: ownerUserID, subjectID: subject.id)
    }

    func refreshGameTimeline(ownerUserID: UUID, subject: GameChatSubject) async throws {
        let generation = await cache.purgeGeneration()
        let previous = await cache.gameTimeline(ownerUserID: ownerUserID, subjectID: subject.id)
        var version = gameTimelineVersions[subject, default: 0]
        var validated = try await gateway.loadGameTimeline(subject: subject, before: nil)
        while true {
            guard version == gameTimelineVersions[subject, default: 0] else { return }
            guard
                await saveGameTimeline(
                    validated, ownerUserID: ownerUserID, subject: subject,
                    older: false, generation: generation, expectedVersion: version)
            else { return }
            version = gameTimelineVersions[subject, default: 0]
            // Revalidate the range loaded on an earlier visit, so a removed result leaves its old position too.
            guard let previous, validated.hasMore, let cursor = validated.nextBefore else { return }
            if let oldest = previous.nextBefore,
                (cursor.at, cursor.itemKind, cursor.key) <= (oldest.at, oldest.itemKind, oldest.key)
            {
                return
            }
            let page = try await gateway.loadGameTimeline(subject: subject, before: cursor)
            validated = validated.merging(page, older: true)
        }
    }

    func loadOlderGameTimeline(ownerUserID: UUID, subject: GameChatSubject) async throws {
        guard let timeline = await cache.gameTimeline(ownerUserID: ownerUserID, subjectID: subject.id),
            timeline.hasMore, let before = timeline.nextBefore
        else { return }
        let generation = await cache.purgeGeneration()
        let version = gameTimelineVersions[subject, default: 0]
        let page = try await gateway.loadGameTimeline(subject: subject, before: before)
        guard version == gameTimelineVersions[subject, default: 0] else { return }
        guard
            await saveGameTimeline(
                page, ownerUserID: ownerUserID, subject: subject,
                older: true, generation: generation, expectedVersion: version)
        else { return }
    }

    nonisolated func liveGameTimelineUpdates(ownerUserID: UUID, subject: GameChatSubject)
        -> AsyncStream<Void>
    {
        let updates = gateway.liveGameTimeline(subject: subject)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                let generation = await cache.purgeGeneration()
                for await page in updates {
                    guard
                        await saveGameTimeline(
                            page, ownerUserID: ownerUserID, subject: subject,
                            older: false, generation: generation)
                    else { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func saveGameTimeline(
        _ page: GameChatTimeline, ownerUserID: UUID, subject: GameChatSubject,
        older: Bool, generation: Int, expectedVersion: Int? = nil
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let cached = await cache.messages(ownerUserID: ownerUserID, subjectID: subject.id)
        let pending = await loadPendingMessages(
            ownerUserID: ownerUserID, coupleID: subject.coupleID, subjectID: subject.id)
        var page = page
        page.messages = await withDeletions(
            ThreadChatMessage.claimingPending(remote: page.messages, cached: cached, pending: pending),
            cached: cached, ownerUserID: ownerUserID)
        guard !Task.isCancelled else { return false }
        if let expectedVersion, expectedVersion != gameTimelineVersions[subject, default: 0] {
            return false
        }
        let previous = await cache.gameTimeline(ownerUserID: ownerUserID, subjectID: subject.id)
        let saved = await cache.saveGameTimeline(
            page, ownerUserID: ownerUserID, subjectID: subject.id,
            older: older, unlessPurgedSince: generation)
        if saved {
            gameTimelineVersions[subject, default: 0] += 1
            let kept = await cache.gameTimeline(ownerUserID: ownerUserID, subjectID: subject.id)
            let keptIDs = Set(kept?.results.map(\.id) ?? [])
            for reference in previous?.results ?? []
                where !keptIDs.contains(reference.id) && page.confirmsRemoval(of: reference)
            {
                await discardRemovedGameResult(
                    ownerUserID: ownerUserID, source: reference.source,
                    generation: generation)
            }
        }
        return saved
    }
}
