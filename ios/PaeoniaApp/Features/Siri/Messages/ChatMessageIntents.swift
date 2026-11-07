import AppIntents
import Foundation

@AppIntent(schema: .messages.editSentMessage)
struct EditChatMessageIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter var message: ChatMessageEntity
    @Parameter var content: AttributedString

    @MainActor
    func perform() async throws -> some IntentResult {
        let couple = try await coupleToActFor()
        let current = try await SiriChats.resolve(message, couple: couple)
        guard current.canEdit(by: couple.ownerUserID) else {
            throw SiriFailure(.siriMessagesCannotEdit)
        }
        let body = String(content.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.unicodeScalars.count <= ThreadChatViewModel.maximumMessageLength
        else {
            throw SiriFailure(.siriMessagesNeedText)
        }
        try await SiriChats.write {
            try await ThreadChatServiceFactory.makeDefault().editMessage(messageID: current.id, body: body)
        }
        if let threadID = current.threadID {
            _ = try? await ThreadChatServiceFactory.makeDefault().refreshMessages(
                ownerUserID: couple.ownerUserID, subjectID: current.subjectID, threadID: threadID)
        }
        return .result()
    }
}

@AppIntent(schema: .messages.unsendMessage)
struct UnsendChatMessageIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter var message: ChatMessageEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let couple = try await coupleToActFor()
        let current = try await SiriChats.resolve(message, couple: couple)
        guard current.canDelete(by: couple.ownerUserID) else {
            throw SiriFailure(.siriMessagesCannotUnsend)
        }
        try await SiriChats.write {
            try await ThreadChatServiceFactory.makeDefault().deleteMessage(
                ownerUserID: couple.ownerUserID,
                message: current, operation: SyncClientOperationFactory.shared.makeOperation())
        }
        await SiriAppContext.shared.syncAfterLocalChange()
        return .result()
    }
}

@AppIntent(schema: .messages.setMessageReadStatus)
struct SetChatMessageReadStatusIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter var message: ChatMessageEntity
    @Parameter var isRead: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let couple = try await coupleToActFor()
        guard isRead else { throw SiriFailure(.siriMessagesCannotUnread) }
        let current = try await SiriChats.resolve(message, couple: couple)
        guard let threadID = current.threadID else { throw SiriFailure(.siriMessagesUnavailable) }
        let service = ThreadChatServiceFactory.makeDefault()
        let through = ThreadChatMessageCursor(createdAt: current.createdAt, messageID: current.id)
        await service.markThreadRead(ownerUserID: couple.ownerUserID, threadID: threadID, through: through)
        await service.markThreadReadOnServer(threadID: threadID, messageID: current.id)
        // As in the chat, the alerts of the messages now read go away.
        let read = await service.cachedMessages(ownerUserID: couple.ownerUserID, subjectID: current.subjectID)
            .filter { ThreadChatMessageCursor(createdAt: $0.createdAt, messageID: $0.id) <= through }
            .map(\.id)
        await DeliveredNotifications.clearMessages(Set(read + [current.id]))
        return .result()
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
struct SendChatMessageReactionIntent: AppIntent {
    static let title = LocalizedStringResource(
        "siri.messages.react", table: "Localizable", comment: "Shortcuts action to react to a message."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter(title: "siri.messages.message") var message: ChatMessageEntity
    @Parameter(title: "siri.messages.emoji") var emoji: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ChatMessageEntity> {
        let couple = try await coupleToActFor()
        let current = try await SiriChats.resolve(message, couple: couple)
        guard !current.isSending, !current.sendFailed, let threadID = current.threadID else {
            throw SiriFailure(.siriMessagesUnavailable)
        }
        guard let emoji = ReactionPalette.normalized(emoji),
            emoji == self.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw SiriFailure(.siriMessagesNeedEmoji)
        }
        guard try await coupleToActFor() == couple else { throw SiriFailure(.siriAccessSignedOut) }
        try await SiriChats.write {
            try await ThreadChatServiceFactory.makeDefault().setReaction(
                ownerUserID: couple.ownerUserID,
                coupleID: couple.coupleID, subjectID: current.subjectID, threadID: threadID,
                item: .message(current.id), emoji: emoji)
        }
        guard
            let updated = await SiriChats.snapshot(for: couple).messages.first(where: {
                $0.id == current.id
            })
        else {
            throw SiriFailure(.siriMessagesUnavailable)
        }
        guard try await coupleToActFor() == couple else { throw SiriFailure(.siriAccessSignedOut) }
        updated.reaction = .attributedString(AttributedString(emoji))
        return .result(value: updated)
    }
}
