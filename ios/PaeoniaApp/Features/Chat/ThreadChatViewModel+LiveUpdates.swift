import Foundation

extension ThreadChatViewModel {
    /// Keeps the chat current while the screen is open, until the calling task is
    /// cancelled. Messages that arrive from the partner, and a thread the partner
    /// starts, show up without a reload. The live results are written to the chat
    /// cache first, so reopening the chat offline shows the same messages.
    func observeLiveUpdates() async {
        guard let ownerUserID = participants.currentUserID, isChatAvailable else { return }

        var followedThreadID: UUID?
        var messageUpdates: Task<Void, Never>?
        let roundUpdates = followRoundUpdates(ownerUserID: ownerUserID)
        let gameUpdates = followGameUpdates(ownerUserID: ownerUserID)
        defer {
            messageUpdates?.cancel()
            roundUpdates?.cancel()
            gameUpdates?.cancel()
        }

        // The queue changes too, so a message that failed to send says so.
        let changes = LocalStoreChanges.changes(in: .threadChat, .pendingOperations)
        // Check once before waiting, in case the thread arrived before this started.
        var shouldRead = true
        var iterator = changes.makeAsyncIterator()
        while shouldRead {
            await readStore(ownerUserID: ownerUserID)
            if let threadID, threadID != followedThreadID {
                followedThreadID = threadID
                messageUpdates?.cancel()
                messageUpdates = followMessageUpdates(ownerUserID: ownerUserID, threadID: threadID)
            }
            // Wait for the next change to this user's chats. Other users' changes are skipped.
            shouldRead = false
            while let change = await iterator.next() {
                if change.ownerUserID == ownerUserID {
                    shouldRead = true
                    break
                }
            }
        }
    }

    private func followGameUpdates(ownerUserID: UUID) -> Task<Void, Never>? {
        guard case let .game(source) = subject else { return nil }
        let coupleID = coupleID
        return Task { @MainActor [weak self, service] in
            for await _ in service.liveGameUpdates(ownerUserID: ownerUserID, coupleID: coupleID, source: source) {
                guard let self else { return }
                self.applyGameResult(await service.cachedGameResult(ownerUserID: ownerUserID, source: source))
            }
        }
    }

    /// The days follow the partner's answers and the chat's thread, so an answer that
    /// opens a day shows without a reload. Other subjects have no days.
    private func followRoundUpdates(ownerUserID: UUID) -> Task<Void, Never>? {
        guard question != nil else { return nil }
        let questionID = subject.id
        let coupleID = coupleID
        return Task { @MainActor [weak self, service] in
            let updates = service.liveRoundUpdates(ownerUserID: ownerUserID, coupleID: coupleID, questionID: questionID)
            for await _ in updates {
                guard let self else { return }
                self.roundsAreConfirmed = true
                await self.readStore(ownerUserID: ownerUserID)
            }
        }
    }

    private func followMessageUpdates(ownerUserID: UUID, threadID: UUID) -> Task<Void, Never> {
        let subjectID = subject.id
        return Task { @MainActor [weak self, service] in
            let updates = service.liveMessageUpdates(
                ownerUserID: ownerUserID,
                subjectID: subjectID,
                threadID: threadID
            )
            for await _ in updates {
                guard let self else { return }
                await self.readStore(ownerUserID: ownerUserID)
            }
        }
    }
}
