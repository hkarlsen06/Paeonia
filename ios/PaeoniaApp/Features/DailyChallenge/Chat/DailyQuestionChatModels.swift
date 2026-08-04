import Foundation

nonisolated struct DailyQuestionThreadSummary: Codable, Equatable, Sendable {
    let threadID: UUID
    let coupleID: UUID
    let instanceID: UUID
    let createdAt: Date
    let updatedAt: Date
    let lastMessageID: UUID?
    let lastMessageAt: Date?
    let lastMessageSenderUserID: UUID?
    let lastMessageBody: String?
}

nonisolated struct DailyQuestionChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let threadID: UUID?
    let instanceID: UUID
    let senderUserID: UUID
    let body: String
    let createdAt: Date
    let clientOperationID: UUID?
    let isSending: Bool
    var sendFailed = false

    static func visibleOrdered(
        remote: [DailyQuestionChatMessage],
        optimistic: [DailyQuestionChatMessage]
    ) -> [DailyQuestionChatMessage] {
        var messagesByID = Dictionary(
            remote.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for message in optimistic where message.isSending || message.sendFailed {
            if let operationID = message.clientOperationID,
               messagesByID.values.contains(where: { $0.clientOperationID == operationID }) {
                continue
            }
            messagesByID[message.id] = message
        }

        return messagesByID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

extension DailyChallengeQuestion {
    var isChatAvailable: Bool {
        hasOwnAnswer && hasPartnerAnswer && canViewPartnerAnswer
    }
}

nonisolated struct CreateDailyQuestionThreadMessageOperationPayload: Codable, Equatable, Sendable {
    let instanceID: UUID
    let coupleID: UUID
    let body: String
}

nonisolated struct SendDailyQuestionThreadMessageOperationPayload: Codable, Equatable, Sendable {
    let instanceID: UUID
    let coupleID: UUID
    let threadID: UUID?
    let body: String
}

nonisolated struct DailyQuestionThreadMessageResponse: Decodable, Equatable, Sendable {
    let threadID: UUID
    let messageID: UUID

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case messageID = "message_id"
    }
}
