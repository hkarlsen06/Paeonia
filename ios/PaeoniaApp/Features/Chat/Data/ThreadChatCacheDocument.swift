import Foundation

nonisolated struct ThreadChatCacheEnvelope<Document: Codable>: Codable {
    let schemaVersion: Int
    let document: Document
}

/// What the cache keeps for a user outside any one chat. It is small, so the
/// cache rewrites it whole.
nonisolated struct ThreadChatCoreDocument: Codable, Equatable {
    /// Newest ids last.
    static let seenAnswerLimit = 1_000

    var summaries: [ThreadChatSummary] = []
    var readThroughByThreadID: [String: Date] = [:]
    var seenPartnerAnswerInstanceIDs: [String] = []

    /// Forgets the oldest ids past the limit. An answer that old no longer shows as new.
    mutating func trimSeenPartnerAnswers() {
        let extra = seenPartnerAnswerInstanceIDs.count - Self.seenAnswerLimit
        if extra > 0 { seenPartnerAnswerInstanceIDs.removeFirst(extra) }
    }
}

/// What the cache keeps for one chat subject: its messages and, for a question, its rounds.
/// Each subject has its own file, so a new message rewrites only that chat.
nonisolated struct ThreadChatSubjectDocument: Codable, Equatable {
    var messages: [ThreadChatMessage] = []
    var rounds: DailyQuestionChatRoundsRow?
}

/// A message the server accepted, in the terms the cache needs to replace the copy
/// shown while it was sending.
nonisolated struct ThreadChatConfirmedSend {
    let subject: ThreadChatSubject
    let coupleID: UUID
    let clientOperationID: UUID
    let threadID: UUID
    let messageID: UUID
    let body: String
    let senderUserID: UUID
    let createdAt: Date
}

nonisolated extension ThreadChatSubjectDocument {
    mutating func storeConfirmedMessage(_ send: ThreadChatConfirmedSend) {
        let index = messages.firstIndex(where: { $0.clientOperationID == send.clientOperationID })
        // A voice message keeps playing from this phone's copy until the server's
        // copy, which carries the uploaded file, replaces it.
        let confirmed = ThreadChatMessage(
            id: send.messageID,
            threadID: send.threadID,
            subjectID: send.subject.id,
            senderUserID: send.senderUserID,
            body: send.body,
            createdAt: send.createdAt,
            clientOperationID: send.clientOperationID,
            isSending: false,
            voice: index.flatMap { messages[$0].voice },
            photos: index.flatMap { messages[$0].photos },
            replyTo: index.flatMap { messages[$0].replyTo }
        )
        if let index {
            messages[index] = confirmed
        } else {
            messages.append(confirmed)
        }
    }
}

nonisolated extension ThreadChatCoreDocument {
    /// The chat's preview shows the newest message the phone knows about.
    mutating func updateSummary(for message: ThreadChatMessage) {
        guard let threadID = message.threadID,
              let index = summaries.firstIndex(where: { $0.threadID == threadID }) else { return }
        let summary = summaries[index]
        summaries[index] = ThreadChatSummary(
            threadID: summary.threadID,
            coupleID: summary.coupleID,
            subject: summary.subject,
            createdAt: summary.createdAt,
            updatedAt: message.createdAt,
            lastMessageID: message.id,
            lastMessageAt: message.createdAt,
            lastMessageSenderUserID: message.senderUserID,
            lastMessageBody: message.body,
            viewerReadThroughAt: summary.viewerReadThroughAt,
            topicKey: summary.topicKey,
            isPrivateTopic: summary.isPrivateTopic
        )
    }

    /// The server leaves a deleted message out of the preview, so a delete made on this
    /// phone does the same until the next read brings the older message.
    mutating func clearLastMessage(ifID messageID: UUID) {
        guard let index = summaries.firstIndex(where: { $0.lastMessageID == messageID }) else { return }
        let summary = summaries[index]
        summaries[index] = ThreadChatSummary(
            threadID: summary.threadID,
            coupleID: summary.coupleID,
            subject: summary.subject,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
            lastMessageID: nil,
            lastMessageAt: nil,
            lastMessageSenderUserID: nil,
            lastMessageBody: nil,
            viewerReadThroughAt: summary.viewerReadThroughAt,
            topicKey: summary.topicKey,
            isPrivateTopic: summary.isPrivateTopic
        )
    }

    mutating func updateSummary(for send: ThreadChatConfirmedSend) {
        if let summaryIndex = summaries.firstIndex(where: { $0.subject == send.subject }) {
            let summary = summaries[summaryIndex]
            summaries[summaryIndex] = ThreadChatSummary(
                threadID: send.threadID,
                coupleID: summary.coupleID,
                subject: send.subject,
                createdAt: summary.createdAt,
                updatedAt: send.createdAt,
                lastMessageID: send.messageID,
                lastMessageAt: send.createdAt,
                lastMessageSenderUserID: send.senderUserID,
                lastMessageBody: send.body,
                viewerReadThroughAt: summary.viewerReadThroughAt,
                topicKey: summary.topicKey,
                isPrivateTopic: summary.isPrivateTopic
            )
        } else {
            summaries.append(
                ThreadChatSummary(
                    threadID: send.threadID,
                    coupleID: send.coupleID,
                    subject: send.subject,
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
