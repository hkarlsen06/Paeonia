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

    /// The newest message came from the partner after `readThrough`, the last time
    /// this user saw the chat on this phone.
    func isUnread(by userID: UUID, readThrough: Date?) -> Bool {
        guard let lastMessageAt, let sender = lastMessageSenderUserID, sender != userID else { return false }
        guard let readThrough else { return true }
        return lastMessageAt > readThrough
    }
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

    /// One-shot reads of a thread can be older than live results that landed while
    /// the request was in flight. The cache holds those newer messages, so a save of
    /// the read keeps every confirmed cached message that the read lacks and that
    /// is newer than the read's newest message. Older ones stay dropped, so a message
    /// the server removed disappears.
    static func keepingNewerCached(
        _ snapshot: [DailyQuestionChatMessage],
        cached: [DailyQuestionChatMessage]
    ) -> [DailyQuestionChatMessage] {
        let newest = snapshot.map(\.createdAt).max() ?? .distantPast
        let snapshotIDs = Set(snapshot.map(\.id))
        return snapshot + cached.filter {
            !$0.isSending && !$0.sendFailed && !snapshotIDs.contains($0.id) && $0.createdAt > newest
        }
    }

    /// Links live server copies of this device's still-sending messages to their
    /// operations. The live query can deliver a message before the send's own
    /// response confirms it, and the server copy carries no client operation id,
    /// so `visibleOrdered` would show it twice.
    ///
    /// A server message that already has an operation id in `cached` keeps it, so
    /// the next live result before the send's response does not drop the link. A
    /// server message that the cache has not seen yet is matched to the oldest
    /// sending message with the same sender and text, and takes over that message's
    /// operation id. A message with the same text sent earlier is already in
    /// `cached` and never matches again.
    static func claimingPending(
        remote: [DailyQuestionChatMessage],
        cached: [DailyQuestionChatMessage],
        pending: [DailyQuestionChatMessage]
    ) -> [DailyQuestionChatMessage] {
        let confirmed = cached.filter { !$0.isSending && !$0.sendFailed }
        let claimedOperations = Dictionary(
            confirmed.compactMap { message in message.clientOperationID.map { (message.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let claimedOperationIDs = Set(claimedOperations.values)
        var waiting = pending
            .filter { message in
                guard message.isSending, let operationID = message.clientOperationID else { return false }
                return !claimedOperationIDs.contains(operationID)
            }
            .sorted { $0.createdAt < $1.createdAt }
        guard !waiting.isEmpty || !claimedOperations.isEmpty else { return remote }

        let knownIDs = Set(confirmed.map(\.id))
        return remote.sorted { $0.createdAt < $1.createdAt }.map { message in
            guard message.clientOperationID == nil else { return message }
            if let operationID = claimedOperations[message.id] {
                return message.confirmed(by: operationID)
            }
            guard !knownIDs.contains(message.id),
                  let index = waiting.firstIndex(where: {
                      $0.senderUserID == message.senderUserID && $0.body == message.body
                  })
            else { return message }
            return message.confirmed(by: waiting.remove(at: index).clientOperationID)
        }
    }

    private func confirmed(by operationID: UUID?) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: id,
            threadID: threadID,
            instanceID: instanceID,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt,
            clientOperationID: operationID,
            isSending: false
        )
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
