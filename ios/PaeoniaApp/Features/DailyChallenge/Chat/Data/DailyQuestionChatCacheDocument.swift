import Foundation

nonisolated struct DailyChatCacheEnvelope: Codable {
    let schemaVersion: Int
    let ownerUserID: UUID
    let document: DailyChatCacheDocument
}

nonisolated struct DailyChatCacheDocument: Codable {
    var summaries: [DailyQuestionThreadSummary] = []
    var messagesByQuestionID: [String: [DailyQuestionChatMessage]] = [:]
    var roundsByQuestionID: [String: DailyQuestionChatRoundsRow] = [:]
    var readThroughByThreadID: [String: Date] = [:]
    var seenPartnerAnswerInstanceIDs: [String] = []
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

nonisolated extension DailyChatCacheDocument {
    mutating func apply(_ send: DailyChatConfirmedSend) {
        storeConfirmedMessage(send)
        updateSummary(for: send)
    }

    mutating func storeConfirmedMessage(_ send: DailyChatConfirmedSend) {
        let key = send.questionID.uuidString
        let index = messagesByQuestionID[key]?.firstIndex(where: {
            $0.clientOperationID == send.clientOperationID
        })
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
            voice: index.flatMap { messagesByQuestionID[key]?[$0].voice },
            photos: index.flatMap { messagesByQuestionID[key]?[$0].photos },
            replyToMessageID: index.flatMap { messagesByQuestionID[key]?[$0].replyToMessageID }
        )
        if let index {
            messagesByQuestionID[key]?[index] = confirmed
        } else {
            messagesByQuestionID[key, default: []].append(confirmed)
        }
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
                viewerReadThroughAt: summary.viewerReadThroughAt
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
