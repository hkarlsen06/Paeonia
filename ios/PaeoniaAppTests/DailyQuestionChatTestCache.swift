import Foundation
import Testing
@testable import PaeoniaApp

actor InMemoryDailyQuestionChatCache: DailyQuestionChatCaching {
    private var storedSummaries: [UUID: [DailyQuestionThreadSummary]] = [:]
    private var storedMessages: [UUID: [UUID: [DailyQuestionChatMessage]]] = [:]
    private var storedRounds: [UUID: [UUID: DailyQuestionChatRoundsRow]] = [:]
    private var generation = 0

    func summaries(ownerUserID: UUID) -> [DailyQuestionThreadSummary] {
        storedSummaries[ownerUserID] ?? []
    }

    func messages(ownerUserID: UUID, questionID: UUID) -> [DailyQuestionChatMessage] {
        storedMessages[ownerUserID]?[questionID] ?? []
    }

    func rounds(ownerUserID: UUID, questionID: UUID) -> DailyQuestionChatRoundsRow? {
        storedRounds[ownerUserID]?[questionID]
    }

    func saveRounds(
        _ rounds: DailyQuestionChatRoundsRow,
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        storedRounds[ownerUserID, default: [:]][questionID] = rounds
        return true
    }

    func saveSummaries(_ summaries: [DailyQuestionThreadSummary], ownerUserID: UUID) {
        storedSummaries[ownerUserID] = summaries
    }

    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID
    ) {
        let optimistic = storedMessages[ownerUserID]?[questionID] ?? []
        storedMessages[ownerUserID, default: [:]][questionID] = DailyQuestionChatMessage.visibleOrdered(
            remote: messages,
            optimistic: optimistic
        )
    }

    func append(_ message: DailyQuestionChatMessage, ownerUserID: UUID) {
        let existing = storedMessages[ownerUserID]?[message.questionID] ?? []
        if let operationID = message.clientOperationID,
           existing.contains(where: { $0.clientOperationID == operationID && !$0.isSending }) {
            return
        }
        storedMessages[ownerUserID, default: [:]][message.questionID, default: []].append(message)
    }

    func markFailed(ownerUserID: UUID, clientOperationID: UUID) {
        guard let questionIDs = storedMessages[ownerUserID]?.keys else { return }
        for questionID in questionIDs {
            guard
                let messages = storedMessages[ownerUserID]?[questionID],
                let index = messages.firstIndex(where: { $0.clientOperationID == clientOperationID })
            else { continue }
            let message = messages[index]
            storedMessages[ownerUserID]?[questionID]?[index] = DailyQuestionChatMessage(
                id: message.id,
                threadID: message.threadID,
                questionID: message.questionID,
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
        guard let questionIDs = storedMessages[ownerUserID]?.keys else { return }
        for questionID in Array(questionIDs) {
            storedMessages[ownerUserID]?[questionID]?.removeAll {
                $0.clientOperationID == clientOperationID && $0.sendFailed
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    func confirm(
        ownerUserID: UUID,
        questionID: UUID,
        coupleID: UUID,
        clientOperationID: UUID,
        threadID: UUID,
        messageID: UUID,
        body: String,
        senderUserID: UUID,
        createdAt: Date
    ) {
        let index = storedMessages[ownerUserID]?[questionID]?.firstIndex(where: {
            $0.clientOperationID == clientOperationID
        })
        let confirmed = DailyQuestionChatMessage(
            id: messageID,
            threadID: threadID,
            questionID: questionID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: clientOperationID,
            isSending: false
        )
        if let index {
            storedMessages[ownerUserID]?[questionID]?[index] = confirmed
        } else {
            storedMessages[ownerUserID, default: [:]][questionID, default: []].append(confirmed)
        }
        if storedSummaries[ownerUserID]?.contains(where: { $0.questionID == questionID }) != true {
            storedSummaries[ownerUserID, default: []].append(
                DailyQuestionThreadSummary(
                    threadID: threadID,
                    coupleID: coupleID,
                    questionID: questionID,
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
    }

    func purgeGeneration() -> Int {
        generation
    }

    func saveMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveMessages(messages, ownerUserID: ownerUserID, questionID: questionID)
        return true
    }

    func mergeMessages(
        _ messages: [DailyQuestionChatMessage],
        ownerUserID: UUID,
        questionID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        let cached = self.messages(ownerUserID: ownerUserID, questionID: questionID)
        saveMessages(
            DailyQuestionChatMessage.keepingNewerCached(messages, cached: cached),
            ownerUserID: ownerUserID,
            questionID: questionID
        )
        return true
    }

    func saveSummaries(
        _ summaries: [DailyQuestionThreadSummary],
        ownerUserID: UUID,
        unlessPurgedSince generation: Int
    ) -> Bool {
        guard generation == self.generation else { return false }
        saveSummaries(summaries, ownerUserID: ownerUserID)
        return true
    }
}
