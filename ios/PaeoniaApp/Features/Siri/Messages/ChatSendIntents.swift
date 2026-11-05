import AppIntents
import Foundation
import GeoToolbox
import UniformTypeIdentifiers

@UnionValue
enum ChatDestination {
    case messagePeople([ChatPersonEntity])
    case messagePerson(ChatPersonEntity)
    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "siri.messages.destination")
    nonisolated static let caseDisplayRepresentations: [Cases: DisplayRepresentation] = [
        .messagePeople: "siri.messages.destination",
        .messagePerson: "siri.messages.destination",
    ]
}

@AppIntent(schema: .messages.sendMessage)
struct SendChatMessageIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter var destination: ChatDestination
    @Parameter var content: AttributedString?
    @Parameter(title: "siri.messages.conversation") var conversation: ChatConversationEntity?
    @Parameter var subject: AttributedString?
    @Parameter(title: "siri.messages.attachments", supportedContentTypes: [.item]) var attachments: [IntentFile]
    @Parameter(title: "siri.messages.audio", supportedContentTypes: [.audio]) var audioMessage: IntentFile?
    @Parameter var locations: [PlaceDescriptor]
    @Parameter var links: [URL]
    @Parameter var scheduledDate: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ChatMessageEntity]> {
        let couple = try await coupleToActFor()
        guard attachments.isEmpty, audioMessage == nil, locations.isEmpty, scheduledDate == nil,
            subject == nil
        else {
            throw SiriFailure(.siriMessagesTextOnly)
        }
        let conversation = try await SiriChats.destination(
            destination, conversation: conversation, couple: couple)
        let text = content.map { String($0.characters) } ?? ""
        let body = ([text].filter { !$0.isEmpty } + links.map(\.absoluteString))
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.unicodeScalars.count <= ThreadChatViewModel.maximumMessageLength
        else {
            throw SiriFailure(.siriMessagesNeedText)
        }
        let service = ThreadChatServiceFactory.makeDefault()
        let pending = await service.hasPendingThreadCreation(
            ownerUserID: couple.ownerUserID,
            coupleID: couple.coupleID, subjectID: conversation.subject.id)
        let message = try await SiriChats.write {
            try await service.queueMessage(
                ownerUserID: couple.ownerUserID, coupleID: couple.coupleID,
                subject: conversation.subject, threadID: conversation.threadID, body: body, photos: nil,
                createThread: conversation.threadID == nil && !pending, replyTo: nil,
                operation: SyncClientOperationFactory.shared.makeOperation())
        }
        await SiriAppContext.shared.syncAfterLocalChange()
        let confirmed =
            await service.cachedMessages(ownerUserID: couple.ownerUserID, subjectID: conversation.subject.id)
            .first { $0.clientOperationID == message.clientOperationID || $0.id == message.id } ?? message
        let entity = ChatMessageEntity(
            id: confirmed.id, author: SiriChats.people(couple)[0], isRead: true,
            conversation: conversation, date: confirmed.createdAt, body: AttributedString(body))
        return .result(value: [entity])
    }
}

@AppIntent(schema: .messages.draftMessage)
struct DraftChatMessageIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.foreground]
    @Parameter var destination: ChatDestination?
    @Parameter var content: AttributedString?
    @Parameter(title: "siri.messages.conversation") var conversation: ChatConversationEntity?
    @Parameter var subject: AttributedString?
    @Parameter(title: "siri.messages.attachments", supportedContentTypes: [.item]) var attachments: [IntentFile]
    @Parameter(title: "siri.messages.audio", supportedContentTypes: [.audio]) var audioMessage: IntentFile?
    @Parameter var locations: [PlaceDescriptor]
    @Parameter var links: [URL]
    @Parameter var scheduledDate: Date?

    @MainActor
    func perform() async throws -> some IntentResult {
        let couple = try await coupleToActFor()
        guard attachments.isEmpty, audioMessage == nil, locations.isEmpty, scheduledDate == nil,
            subject == nil
        else {
            throw SiriFailure(.siriMessagesTextOnly)
        }
        let conversation = try await SiriChats.destination(
            destination, conversation: conversation, couple: couple)
        let text = content.map { String($0.characters) } ?? ""
        let body = ([text].filter { !$0.isEmpty } + links.map(\.absoluteString)).joined(separator: "\n")
        guard body.unicodeScalars.count <= ThreadChatViewModel.maximumMessageLength else {
            throw SiriFailure(.siriMessagesNeedText)
        }
        SiriAppContext.shared.messageDraft = SiriMessageDraft(
            ownerUserID: couple.ownerUserID,
            subject: conversation.subject, body: body)
        SiriAppContext.shared.open(SiriChats.deepLink(conversation))
        return .result()
    }
}

extension SiriChats {
    static func destination(
        _ destination: ChatDestination?, conversation: ChatConversationEntity?, couple: SiriCouple
    ) async throws -> ChatConversationEntity {
        let snapshot = await snapshot(for: couple)
        try validateRecipient(destination, couple: couple)
        if let entity = conversation {
            guard let current = snapshot.conversations.first(where: { $0.id == entity.id }) else {
                throw SiriFailure(.siriMessagesUnavailable)
            }
            return current
        }
        guard let conversation = snapshot.conversations.first(where: { $0.subject == .couple }) else {
            throw SiriFailure(.siriMessagesUnavailable)
        }
        return conversation
    }

    static func validateRecipient(_ destination: ChatDestination?, couple: SiriCouple) throws {
        switch destination {
        case .messagePerson(let person):
            guard person.id == couple.partnerUserID else { throw SiriFailure(.siriMessagesPartnerOnly) }
        case .messagePeople(let people):
            guard !people.isEmpty, people.allSatisfy({ $0.id == couple.partnerUserID }) else {
                throw SiriFailure(.siriMessagesPartnerOnly)
            }
        case nil: break
        }
    }

    static func deepLink(_ conversation: ChatConversationEntity) -> PaeoniaDeepLink {
        switch conversation.subject {
        case .couple: .coupleChat
        case .memory(let id): .memory(memoryID: id, showsComments: true)
        case .story(let id): .story(storyID: id, showsReplies: true)
        case .question(let id): .dailyChat(questionID: id)
        case .game(let game): .gameChat(kind: game.kind)
        }
    }
}

struct SiriMessageDraft {
    let id = UUID()
    let ownerUserID: UUID
    let subject: ThreadChatSubject
    let body: String

    func appending(to existing: String) -> String {
        guard !existing.isEmpty else { return body }
        guard !body.isEmpty else { return existing }
        return existing + "\n\n" + body
    }
}
