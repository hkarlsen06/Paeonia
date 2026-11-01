import Foundation

nonisolated struct MediaAlternativeCacheUpdater: Sendable {
    let chat: any ThreadChatCaching
    let stories: any StoriesCaching
    let daily: any DailyChallengeSnapshotCaching
    let topics: FileTopicsCache?
    let guessMySpot: (any GuessMySpotCaching)?
    let drawings: (any GamesCaching)?
    let widgetCanvas: (any WidgetDrawingDescriptionCaching)?
    let creatures: (any ExquisiteCorpseCaching)?

    init(chat: any ThreadChatCaching, stories: any StoriesCaching, daily: any DailyChallengeSnapshotCaching,
         topics: FileTopicsCache? = nil, guessMySpot: (any GuessMySpotCaching)? = nil,
         drawings: (any GamesCaching)? = nil, creatures: (any ExquisiteCorpseCaching)? = nil,
         widgetCanvas: (any WidgetDrawingDescriptionCaching)? = nil) {
        self.chat = chat
        self.stories = stories
        self.daily = daily
        self.topics = topics
        self.guessMySpot = guessMySpot
        self.drawings = drawings
        self.creatures = creatures
        self.widgetCanvas = widgetCanvas
    }

    static let live = Self(chat: FileThreadChatCache.shared, stories: FileStoriesCache.shared,
                           daily: FileDailyChallengeSnapshotCache.live(), topics: .shared,
                           guessMySpot: FileGuessMySpotCache.shared, drawings: FileGamesCache.shared,
                           creatures: FileExquisiteCorpseCache.shared, widgetCanvas: WidgetCanvasService.shared)

    nonisolated struct Stamp: Sendable {
        let privacy: LocalPrivacyWriteGuard.Token
        let chat: Int
        let stories: Int
        let daily: DailyChallengeLiveWriteClock.Mark
        let guessMySpot: Int?
    }

    func stamp(ownerUserID: UUID) async -> Stamp {
        Stamp(privacy: LocalPrivacyWriteGuard.shared.token(ownerUserID: ownerUserID),
              chat: await chat.purgeGeneration(), stories: await stories.purgeGeneration,
              daily: DailyChallengeLiveWriteClock.shared.count(ownerUserID: ownerUserID),
              guessMySpot: await guessMySpot?.historyTicket())
    }

    func isCurrent(_ stamp: Stamp) async -> Bool {
        guard LocalPrivacyWriteGuard.shared.isCurrent(stamp.privacy) else { return false }
        return await chat.purgeGeneration() == stamp.chat
    }

    func apply(_ edit: MediaAlternativeEdit, ownerUserID: UUID, operation: SyncClientOperation, stamp: Stamp,
               widgetRevisionVersion: Int64? = nil) async {
        await MediaAlternativeCacheWrites.shared.perform(
            ownerUserID: ownerUserID, edit: edit, operation: operation, privacyToken: stamp.privacy,
            widgetRevisionVersion: widgetRevisionVersion
        ) {
            await applyToCaches(edit, ownerUserID: ownerUserID, stamp: stamp)
            if case let .widgetDrawing(revisionID) = edit.target, await isCurrent(stamp) {
                let update: WidgetDrawingDescriptionUpdate = widgetRevisionVersion.map {
                    .accepted(text: edit.text.trimmedNonEmpty, version: $0, operationID: operation.id)
                } ?? .queued(text: edit.text, operationID: operation.id)
                await widgetCanvas?.updateDescription(update, revisionID: revisionID, privacyToken: stamp.privacy)
            }
        }
    }

    private func applyToCaches(_ edit: MediaAlternativeEdit, ownerUserID: UUID, stamp: Stamp) async {
        guard await isCurrent(stamp) else { return }
        await chat.updateMediaAlternative(edit, ownerUserID: ownerUserID, unlessPurgedSince: stamp.chat)
        if case .drawAndGuess = edit.target {
            await drawings?.updateDrawingDescription(edit, ownerUserID: ownerUserID, privacyToken: stamp.privacy)
            LocalStoreChanges.post(.games, ownerUserID: ownerUserID)
        }
        if case .exquisiteCorpse = edit.target {
            await creatures?.updateDrawingDescription(edit, ownerUserID: ownerUserID, privacyToken: stamp.privacy)
            LocalStoreChanges.post(.games, ownerUserID: ownerUserID)
        }
        if case .guessMySpot = edit.target, let ticket = stamp.guessMySpot {
            await guessMySpot?.updatePhotoDescription(edit, ownerUserID: ownerUserID, ticket: ticket)
            LocalStoreChanges.post(.games, ownerUserID: ownerUserID)
        }
        if case let .story(storyID) = edit.target {
            _ = await stories.update(ownerUserID: ownerUserID, ifGeneration: stamp.stories) { snapshot in
                guard let index = snapshot.stories.firstIndex(where: {
                    $0.id == storyID && $0.authorUserID == ownerUserID
                })
                else { return }
                snapshot.stories[index].accessibilityText = edit.text.trimmedNonEmpty
            }
            LocalStoreChanges.post(.stories, ownerUserID: ownerUserID)
        }
        if case let .daily(answerID) = edit.target {
            DailyChallengeLiveWriteClock.shared.updateMediaAlternative(
                answerID: answerID, text: edit.text, ownerUserID: ownerUserID, since: stamp.daily, cache: daily
            )
            LocalStoreChanges.post(.dailyChallenge, ownerUserID: ownerUserID)
            await topics?.updateMediaAlternative(answerID: answerID, text: edit.text,
                                                  ownerUserID: ownerUserID, privacyToken: stamp.privacy)
        }
    }
}

nonisolated extension ThreadChatSubjectDocument {
    mutating func applyMediaAlternative(_ edit: MediaAlternativeEdit, ownerUserID: UUID) {
        messages = messages.map { $0.applyingMediaAlternative(edit, ownerUserID: ownerUserID) }
        if var timeline = gameTimeline {
            timeline.messages = timeline.messages.map { $0.applyingMediaAlternative(edit, ownerUserID: ownerUserID) }
            gameTimeline = timeline
        }
        if case let .daily(answerID) = edit.target, let current = rounds {
            rounds = DailyQuestionChatRoundsRow(
                threadID: current.threadID, questions: current.questions,
                answerDetails: current.answerDetails.map {
                    $0.applyingMediaAlternative(answerID: answerID, text: edit.text, ownerUserID: ownerUserID)
                },
                reactions: current.reactions
            )
        }
    }
}

nonisolated extension ThreadChatMessage {
    func applyingMediaAlternative(_ edit: MediaAlternativeEdit, ownerUserID: UUID) -> Self {
        guard case let .chat(messageID, assetID) = edit.target, id == messageID,
              senderUserID == ownerUserID, !isDeleted, !isUnsent else { return self }
        var updated = self
        if updated.voice?.mediaAssetID == assetID { updated.voice?.transcript = edit.text.trimmedNonEmpty }
        updated.photos = photos?.map { photo in
            guard photo.mediaAssetID == assetID else { return photo }
            var updated = photo
            updated.accessibilityText = edit.text.trimmedNonEmpty
            return updated
        }
        return updated
    }
}

nonisolated extension DailyAnswerDetailRow {
    func applyingMediaAlternative(answerID: UUID, text: String, ownerUserID: UUID) -> Self {
        guard self.answerID == answerID, answerUserID == ownerUserID, isOwnAnswer, canViewAnswer, !mediaAssetIDs.isEmpty
        else { return self }
        var updated = self
        updated.mediaAccessibilityText = text.trimmedNonEmpty
        return updated
    }
}
