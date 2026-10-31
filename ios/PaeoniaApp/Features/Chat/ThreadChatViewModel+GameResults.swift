import Foundation

extension ThreadChatViewModel {
    /// Expanded old results follow their own query, even outside the newest timeline page.
    func observeExpandedGameResults() async {
        guard let ownerID = participants.currentUserID else { return }
        let sources = gameReferences.filter { expandedGameResultIDs.contains($0.id) }.map(\.source)
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { [weak self, service, coupleID] in
                    let updates = service.liveGameResultUpdates(
                        ownerUserID: ownerID, coupleID: coupleID, source: source)
                    for await _ in updates {
                        guard !Task.isCancelled else { break }
                        let result = await service.cachedGameResult(ownerUserID: ownerID, source: source)
                        await self?.applyExpandedGameResult(result, source: source)
                    }
                }
            }
        }
    }

    private func applyExpandedGameResult(_ result: GameConversationResult?, source: GameConversationSource) {
        guard expandedGameResultIDs.contains(source.id) else { return }
        gameResults[source.id] = result
        if result == nil {
            gameResultLoadStates[source.id] = .removed
            gameReferences.removeAll { $0.id == source.id }
            expandedGameResultIDs.remove(source.id)
            if case .gameResult(let target)? = replyTarget, target.source == source { replyTarget = nil }
        }
    }

    var gameResultCards: [GameChatResultCard] {
        gameReferences.map {
            GameChatResultCard(
                reference: $0, result: gameResults[$0.id],
                isExpanded: expandedGameResultIDs.contains($0.id),
                loadState: gameResultLoadStates[$0.id] ?? .loading)
        }
    }

    /// A result opened from history stays reachable even before older pages finish loading.
    func focusGameResult(source: GameConversationSource, result: GameConversationResult?) async {
        guard case .game(let game) = subject, source.kind == game.kind,
            let ownerUserID = participants.currentUserID
        else { return }
        if let result {
            await service.keepGameResult(result, ownerUserID: ownerUserID, source: source)
        }
        // Read common pages until the result is in its real place among messages.
        if !gameReferences.contains(where: { $0.source == source }) {
            try? await service.refreshGameTimeline(ownerUserID: ownerUserID, subject: game)
            await readStore(ownerUserID: ownerUserID)
            while hasOlderMessages && !gameReferences.contains(where: { $0.source == source })
                && !Task.isCancelled
            {
                let previous = gameReferences.count + messages.count
                await loadOlderMessages()
                if previous == gameReferences.count + messages.count { break }
            }
        }
        guard gameReferences.contains(where: { $0.source == source }) else { return }
        expandedGameResultIDs.insert(source.id)
        await loadGameResult(source)
        focusedGameResultID = source.id
    }

    func toggleGameResult(_ reference: GameChatResultReference) async {
        if expandedGameResultIDs.contains(reference.id) {
            expandedGameResultIDs.remove(reference.id)
        } else {
            expandedGameResultIDs.insert(reference.id)
            await loadGameResult(reference.source)
        }
    }

    func refreshExpandedGameResults() async {
        for reference in gameReferences where expandedGameResultIDs.contains(reference.id) {
            await loadGameResult(reference.source)
        }
    }

    func loadGameResult(_ source: GameConversationSource) async {
        guard let ownerUserID = participants.currentUserID else { return }
        if let cached = await service.cachedGameResult(ownerUserID: ownerUserID, source: source) {
            gameResults[source.id] = cached
        }
        gameResultLoadStates[source.id] = .loading
        do {
            let result = try await service.refreshGameResult(
                ownerUserID: ownerUserID, coupleID: coupleID, source: source)
            gameResults[source.id] = result
            if result == nil {
                gameResultLoadStates[source.id] = .removed
                gameReferences.removeAll { $0.source == source }
                if case .gameResult(let target)? = replyTarget, target.source == source {
                    replyTarget = nil
                }
            }
        } catch {
            if !error.isCancellation {
                gameResultLoadStates[source.id] = PaeoniaFailure(error) == .offline ? .offline : .failed
            }
        }
    }

    func setReplyTarget(_ reference: GameChatResultReference) {
        guard isChatAvailable, editTarget == nil, gameReferences.contains(reference) else { return }
        replyTarget = .gameResult(reference)
        composerFocusRequest += 1
    }
}

nonisolated struct GameChatResultCard: Hashable, Sendable {
    let reference: GameChatResultReference
    let result: GameConversationResult?
    let isExpanded: Bool
    let loadState: GameConversationLoadState
}
