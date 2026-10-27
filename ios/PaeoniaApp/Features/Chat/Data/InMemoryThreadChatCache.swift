#if DEBUG
    import Foundation

    actor InMemoryThreadChatCache: ThreadChatCaching {
        private var storedSummaries: [UUID: [ThreadChatSummary]] = [:]
        private var storedMessages: [UUID: [UUID: [ThreadChatMessage]]] = [:]
        private var storedRounds: [UUID: [UUID: DailyQuestionChatRoundsRow]] = [:]
        private var storedGames: [UUID: [UUID: GameConversationResult]] = [:]
        private var generation = 0

        func summaries(ownerUserID: UUID) -> [ThreadChatSummary] {
            storedSummaries[ownerUserID] ?? []
        }

        func messages(ownerUserID: UUID, subjectID: UUID) -> [ThreadChatMessage] {
            storedMessages[ownerUserID]?[subjectID] ?? []
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
                existing.contains(where: { $0.clientOperationID == operationID && !$0.isSending })
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
                    isSending: false,
                    sendFailed: true
                )
                return
            }
        }

        func discardFailed(ownerUserID: UUID, clientOperationID: UUID) {
            guard let subjectIDs = storedMessages[ownerUserID]?.keys else { return }
            for subjectID in Array(subjectIDs) {
                storedMessages[ownerUserID]?[subjectID]?.removeAll {
                    $0.clientOperationID == clientOperationID && $0.sendFailed
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
            let subjectID = subject.id
            let index = storedMessages[ownerUserID]?[subjectID]?.firstIndex(where: {
                $0.clientOperationID == clientOperationID
            })
            let confirmed = ThreadChatMessage(
                id: messageID,
                threadID: threadID,
                subjectID: subjectID,
                senderUserID: senderUserID,
                body: body,
                createdAt: createdAt,
                clientOperationID: clientOperationID,
                isSending: false
            )
            if let index {
                storedMessages[ownerUserID]?[subjectID]?[index] = confirmed
            } else {
                storedMessages[ownerUserID, default: [:]][subjectID, default: []].append(confirmed)
            }
            if storedSummaries[ownerUserID]?.contains(where: { $0.subject == subject }) != true {
                storedSummaries[ownerUserID, default: []].append(
                    ThreadChatSummary(
                        threadID: threadID,
                        coupleID: coupleID,
                        subject: subject,
                        createdAt: createdAt,
                        updatedAt: createdAt,
                        lastMessageID: messageID,
                        lastMessageAt: createdAt,
                        lastMessageSenderUserID: senderUserID,
                        lastMessageBody: body
                    )
                )
            }
        }

        func clearAll() {
            generation += 1
            storedSummaries = [:]
            storedMessages = [:]
            storedRounds = [:]
            storedGames = [:]
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
