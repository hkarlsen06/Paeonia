import Foundation

nonisolated struct DailyChatCacheEnvelope<Document: Codable>: Codable {
    let schemaVersion: Int
    let document: Document
}

/// What the cache keeps for a user outside any one question. It is small, so the
/// cache rewrites it whole.
nonisolated struct DailyChatCoreDocument: Codable, Equatable {
    /// Newest ids last.
    static let seenAnswerLimit = 1_000

    var summaries: [DailyQuestionThreadSummary] = []
    var readThroughByThreadID: [String: Date] = [:]
    var seenPartnerAnswerInstanceIDs: [String] = []

    /// Forgets the oldest ids past the limit. An answer that old no longer shows as new.
    mutating func trimSeenPartnerAnswers() {
        let extra = seenPartnerAnswerInstanceIDs.count - Self.seenAnswerLimit
        if extra > 0 { seenPartnerAnswerInstanceIDs.removeFirst(extra) }
    }
}

/// What the cache keeps for one question: its chat messages and its rounds. Each question
/// has its own file, so a new message rewrites only that chat.
nonisolated struct DailyChatQuestionDocument: Codable, Equatable {
    var messages: [DailyQuestionChatMessage] = []
    var rounds: DailyQuestionChatRoundsRow?
}

/// A message the server accepted, in the terms the cache needs to replace the copy
/// shown while it was sending.
nonisolated struct DailyChatConfirmedSend {
    let questionID: UUID
    let coupleID: UUID
    let clientOperationID: UUID
    let threadID: UUID
    let messageID: UUID
    let body: String
    let senderUserID: UUID
    let createdAt: Date
}

nonisolated extension DailyChatQuestionDocument {
    mutating func storeConfirmedMessage(_ send: DailyChatConfirmedSend) {
        let index = messages.firstIndex(where: { $0.clientOperationID == send.clientOperationID })
        // A voice message keeps playing from this phone's copy until the server's
        // copy, which carries the uploaded file, replaces it.
        let confirmed = DailyQuestionChatMessage(
            id: send.messageID,
            threadID: send.threadID,
            questionID: send.questionID,
            senderUserID: send.senderUserID,
            body: send.body,
            createdAt: send.createdAt,
            clientOperationID: send.clientOperationID,
            isSending: false,
            voice: index.flatMap { messages[$0].voice },
            photos: index.flatMap { messages[$0].photos },
            replyToMessageID: index.flatMap { messages[$0].replyToMessageID }
        )
        if let index {
            messages[index] = confirmed
        } else {
            messages.append(confirmed)
        }
    }
}

nonisolated extension DailyChatCoreDocument {
    /// The chat's preview shows the newest message the phone knows about.
    mutating func updateSummary(for message: DailyQuestionChatMessage) {
        guard let threadID = message.threadID,
              let index = summaries.firstIndex(where: { $0.threadID == threadID }) else { return }
        let summary = summaries[index]
        summaries[index] = DailyQuestionThreadSummary(
            threadID: summary.threadID,
            coupleID: summary.coupleID,
            questionID: summary.questionID,
            createdAt: summary.createdAt,
            updatedAt: message.createdAt,
            lastMessageID: message.id,
            lastMessageAt: message.createdAt,
            lastMessageSenderUserID: message.senderUserID,
            lastMessageBody: message.body,
            viewerReadThroughAt: summary.viewerReadThroughAt,
            topicKey: summary.topicKey,
            isAdultTopic: summary.isAdultTopic
        )
    }

    mutating func updateSummary(for send: DailyChatConfirmedSend) {
        if let summaryIndex = summaries.firstIndex(where: { $0.questionID == send.questionID }) {
            let summary = summaries[summaryIndex]
            summaries[summaryIndex] = DailyQuestionThreadSummary(
                threadID: send.threadID,
                coupleID: summary.coupleID,
                questionID: send.questionID,
                createdAt: summary.createdAt,
                updatedAt: send.createdAt,
                lastMessageID: send.messageID,
                lastMessageAt: send.createdAt,
                lastMessageSenderUserID: send.senderUserID,
                lastMessageBody: send.body,
                viewerReadThroughAt: summary.viewerReadThroughAt,
                topicKey: summary.topicKey,
                isAdultTopic: summary.isAdultTopic
            )
        } else {
            summaries.append(
                DailyQuestionThreadSummary(
                    threadID: send.threadID,
                    coupleID: send.coupleID,
                    questionID: send.questionID,
                    createdAt: send.createdAt,
                    updatedAt: send.createdAt,
                    lastMessageID: send.messageID,
                    lastMessageAt: send.createdAt,
                    lastMessageSenderUserID: send.senderUserID,
                    lastMessageBody: send.body
                )
            )
        }
    }
}
