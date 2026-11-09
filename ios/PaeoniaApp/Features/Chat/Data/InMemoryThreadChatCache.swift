#if DEBUG
    import Foundation

    actor InMemoryThreadChatCache: ThreadChatCaching {
        private var storedSummaries: [UUID: [ThreadChatSummary]] = [:]
        private var storedMessages: [UUID: [UUID: [ThreadChatMessage]]] = [:]
        private var storedRounds: [UUID: [UUID: DailyQuestionChatRoundsRow]] = [:]
        private var storedGames: [UUID: [UUID: GameConversationResult]] = [:]
        private var storedTimelines: [UUID: [UUID: GameChatTimeline]] = [:]
        private var generation = 0
        private var storedReadMarks: [UUID: [UUID: ThreadChatMessageCursor]] = [:]
        private var seenAnswers: [UUID: Set<UUID>] = [:]

        func readMarks(ownerUserID: UUID) -> [UUID: ThreadChatMessageCursor] {
            storedReadMarks[ownerUserID] ?? [:]
        }

        func markRead(ownerUserID: UUID, threadID: UUID, through cursor: ThreadChatMessageCursor) -> Bool {
            if let current = storedReadMarks[ownerUserID]?[threadID], current >= cursor { return false }
            storedReadMarks[ownerUserID, default: [:]][threadID] = cursor
            return true
        }

        func seenPartnerAnswers(ownerUserID: UUID) -> Set<UUID> { seenAnswers[ownerUserID] ?? [] }

        func markPartnerAnswerSeen(ownerUserID: UUID, instanceID: UUID) -> Bool {
            seenAnswers[ownerUserID, default: []].insert(instanceID).inserted
        }

        func updateMediaAlternative(
            _ edit: MediaAlternativeEdit, ownerUserID: UUID, unlessPurgedSince generation: Int
        ) {
            guard generation == self.generation else { return }
            for key in (storedMessages[ownerUserID] ?? [:]).keys {
                storedMessages[ownerUserID]?[key] = storedMessages[ownerUserID]?[key]?.map {
                    $0.applyingMediaAlternative(edit, ownerUserID: ownerUserID)
                }
            }
            for key in (storedTimelines[ownerUserID] ?? [:]).keys {
                guard var timeline = storedTimelines[ownerUserID]?[key] else { continue }
                timeline.messages = timeline.messages.map {
                    $0.applyingMediaAlternative(edit, ownerUserID: ownerUserID)
                }
                storedTimelines[ownerUserID]?[key] = timeline
            }
            if case let .daily(answerID) = edit.target {
                for (key, current) in storedRounds[ownerUserID] ?? [:] {
                    storedRounds[ownerUserID]?[key] = DailyQuestionChatRoundsRow(
                        threadID: current.threadID, questions: current.questions,
                        answerDetails: current.answerDetails.map {
                            $0.applyingMediaAlternative(answerID: answerID, text: edit.text, ownerUserID: ownerUserID)
                        }, reactions: current.reactions
                    )
                }
            }
            LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
        }

        func summaries(ownerUserID: UUID) -> [ThreadChatSummary] {
            storedSummaries[ownerUserID] ?? []
        }

        func messages(ownerUserID: UUID, subjectID: UUID) -> [ThreadChatMessage] {
            storedMessages[ownerUserID]?[subjectID] ?? []
        }

        func gameTimeline(ownerUserID: UUID, subjectID: UUID) -> GameChatTimeline? {
            storedTimelines[ownerUserID]?[subjectID]
        }

        @discardableResult
        func saveGameTimeline(_ timeline: GameChatTimeline, ownerUserID: UUID, subjectID: UUID,
                              older: Bool, unlessPurgedSince generation: Int) -> Bool {
            guard generation == self.generation else { return false }
            let merged = storedTimelines[ownerUserID]?[subjectID]?.merging(timeline, older: older) ?? timeline
            storedTimelines[ownerUserID, default: [:]][subjectID] = merged
            saveMessages(merged.messages, ownerUserID: ownerUserID, subjectID: subjectID)
            LocalStoreChanges.post(.threadChat, ownerUserID: ownerUserID)
            return true
        }

        func gameResult(ownerUserID: UUID, subjectID: UUID) -> GameConversationResult? {
            storedGames[ownerUserID]?[subjectID]
        }

        func saveGameResult(
            _ result: GameConversationResult?, ownerUserID: UUID, subjectID: UUID, unlessPurgedSince generation: Int
        ) -> Bool {
            guard generation == self.generation else { return false }
            storedGames[ownerUserID, default: [:]][subjectID] = result
            return true
        }

        func rounds(ownerUserID: UUID, subjectID: UUID) -> DailyQuestionChatRoundsRow? {
            storedRounds[ownerUserID]?[subjectID]
        }

        func saveRounds(
            _ rounds: DailyQuestionChatRoundsRow,
            ownerUserID: UUID,
            subjectID: UUID,
            unlessPurgedSince generation: Int
        ) -> Bool {
            guard generation == self.generation else { return false }
            storedRounds[ownerUserID, default: [:]][subjectID] = rounds
            return true
        }

        @discardableResult
        func saveSummaries(_ summaries: [ThreadChatSummary], ownerUserID: UUID) -> Bool {
            let changed = storedSummaries[ownerUserID] != summaries
            storedSummaries[ownerUserID] = summaries
            return changed
        }

        func saveMessages(
            _ messages: [ThreadChatMessage],
            ownerUserID: UUID,
            subjectID: UUID
        ) {
            let optimistic = storedMessages[ownerUserID]?[subjectID] ?? []
            storedMessages[ownerUserID, default: [:]][subjectID] = ThreadChatMessage.visibleOrdered(
                remote: messages,
                optimistic: optimistic
            )
        }

        func append(_ message: ThreadChatMessage, ownerUserID: UUID) {
            let existing = storedMessages[ownerUserID]?[message.subjectID] ?? []
            if let operationID = message.clientOperationID,
                existing.contains(where: { $0.clientOperationID == operationID && $0.delivery != .sending })
            {
                return
            }
            storedMessages[ownerUserID, default: [:]][message.subjectID, default: []].append(message)
        }

        func markFailed(ownerUserID: UUID, clientOperationID: UUID) {
            guard let subjectIDs = storedMessages[ownerUserID]?.keys else { return }
            for subjectID in subjectIDs {
                guard
                    let messages = storedMessages[ownerUserID]?[subjectID],
                    let index = messages.firstIndex(where: { $0.clientOperationID == clientOperationID })
                else { continue }
                let message = messages[index]
                storedMessages[ownerUserID]?[subjectID]?[index] = ThreadChatMessage(
                    id: message.id,
                    threadID: message.threadID,
                    subjectID: message.subjectID,
                    senderUserID: message.senderUserID,
                    body: message.body,
                    createdAt: message.createdAt,
                    clientOperationID: clientOperationID,
                    delivery: .failed,
                    voice: message.voice,
                    photos: message.photos,
                    replyTo: message.replyTo
                )
                return
            }
        }

        func discardFailed(ownerUserID: UUID, clientOperationID: UUID) {
            guard let subjectIDs = storedMessages[ownerUserID]?.keys else { return }
            for subjectID in Array(subjectIDs) {
                storedMessages[ownerUserID]?[subjectID]?.removeAll {
                    $0.clientOperationID == clientOperationID && $0.delivery == .failed
                }
            }
        }

        func discardUnsent(ownerUserID: UUID, subjectID: UUID, clientOperationID: UUID) {
            storedMessages[ownerUserID]?[subjectID]?.removeAll {
                $0.clientOperationID == clientOperationID && $0.isUnsent
            }
        }

        @discardableResult
        func markDeleted(ownerUserID: UUID, subjectID: UUID, messageID: UUID, at date: Date) -> [UUID] {
            guard
                let index = storedMessages[ownerUserID]?[subjectID]?.firstIndex(where: {
                    $0.id == messageID && !$0.isDeleted
                }), let message = storedMessages[ownerUserID]?[subjectID]?[index]
            else { return [] }
            var gone = message.takenBack
            gone.deletedAt = date
            storedMessages[ownerUserID]?[subjectID]?[index] = gone
            return message.mediaAssetIDs
        }

        @discardableResult
        func markDeletedInAnyChat(ownerUserID: UUID, messageID: UUID, at date: Date) -> [UUID] {
            let subjectIDs = storedMessages[ownerUserID].map { Array($0.keys) } ?? []
            for subjectID in subjectIDs
            where storedMessages[ownerUserID]?[subjectID]?.contains(where: { $0.id == messageID }) == true {
                return markDeleted(ownerUserID: ownerUserID, subjectID: subjectID, messageID: messageID, at: date)
            }
            return []
        }

        // swiftlint:disable:next function_parameter_count
        func confirm(
            ownerUserID: UUID,
            subject: ThreadChatSubject,
            coupleID: UUID,
            clientOperationID: UUID,
            threadID: UUID,
            messageID: UUID,
            body: String,
            senderUserID: UUID,
            createdAt: Date
        ) {
            let send = ThreadChatConfirmedSend(
                subject: subject, coupleID: coupleID, clientOperationID: clientOperationID,
                threadID: threadID, messageID: messageID, body: body,
                senderUserID: senderUserID, createdAt: createdAt
            )
            var document = ThreadChatSubjectDocument(messages: storedMessages[ownerUserID]?[subject.id] ?? [])
            document.storeConfirmedMessage(send)
            storedMessages[ownerUserID, default: [:]][subject.id] = document.messages
            var core = ThreadChatCoreDocument(summaries: storedSummaries[ownerUserID] ?? [])
            core.updateSummary(for: send)
            storedSummaries[ownerUserID] = core.summaries
        }

        func clearAll() {
            storedReadMarks = [:]
            seenAnswers = [:]
            generation += 1
            storedSummaries = [:]
            storedMessages = [:]
            storedRounds = [:]
            storedGames = [:]
            storedTimelines = [:]
        }

        func purgeGeneration() -> Int {
            generation
        }

        func saveMessages(
            _ messages: [ThreadChatMessage],
            ownerUserID: UUID,
            subjectID: UUID,
            unlessPurgedSince generation: Int
        ) -> Bool {
            guard generation == self.generation else { return false }
            saveMessages(messages, ownerUserID: ownerUserID, subjectID: subjectID)
            return true
        }

        func mergeMessages(
            _ messages: [ThreadChatMessage],
            ownerUserID: UUID,
            subjectID: UUID,
            unlessPurgedSince generation: Int
        ) -> Bool {
            guard generation == self.generation else { return false }
            let cached = self.messages(ownerUserID: ownerUserID, subjectID: subjectID)
            saveMessages(
                ThreadChatMessage.keepingNewerCached(messages, cached: cached),
                ownerUserID: ownerUserID,
                subjectID: subjectID
            )
            return true
        }

        func saveSummaries(
            _ summaries: [ThreadChatSummary],
            ownerUserID: UUID,
            unlessPurgedSince generation: Int
        ) -> Bool {
            guard generation == self.generation else { return false }
            saveSummaries(summaries, ownerUserID: ownerUserID)
            return true
        }
    }

#endif
