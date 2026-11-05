import AppIntents
import CoreSpotlight
import Foundation
import GeoToolbox
import LinkPresentation

@AppEntity(schema: .messages.messagePerson)
struct ChatPersonEntity: IndexedEntity, OwnershipProvidingEntity {
    static let defaultQuery = ChatPersonQuery()
    let id: UUID
    let name: String
    var person: IntentPerson
    var ownership: EntityOwnership { .shared }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }

    init(id: UUID, name: String, isMe: Bool) {
        self.id = id
        self.name = name
        person = IntentPerson(
            identifier: .applicationDefined(id.uuidString), name: .displayName(name), handle: nil,
            isMe: isMe)
    }
}

@AppEntity(schema: .messages.conversation)
struct ChatConversationEntity: IndexedEntity, OwnershipProvidingEntity {
    static let defaultQuery = ChatConversationQuery()
    let id: UUID
    let subject: ThreadChatSubject
    let threadID: UUID?
    var recipients: [ChatPersonEntity]
    var displayName: String
    var previewText: AttributedString
    var conversationName: String?
    var isRead: Bool
    var attributes: Set<ChatConversationAttribute>
    var dateLastActive: Date?
    var ownership: EntityOwnership { .shared }
    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(displayName)", subtitle: "\(previewText)")
    }

    init(
        id: UUID, subject: ThreadChatSubject, threadID: UUID?, recipients: [ChatPersonEntity],
        displayName: String, previewText: AttributedString, conversationName: String?, isRead: Bool,
        dateLastActive: Date?
    ) {
        self.id = id
        self.subject = subject
        self.threadID = threadID
        self.recipients = recipients
        self.displayName = displayName
        self.previewText = previewText
        self.conversationName = conversationName
        self.isRead = isRead
        self.dateLastActive = dateLastActive
        attributes = []
    }
}

@AppEnum(schema: .messages.conversationAttribute)
enum ChatConversationAttribute: String {
    case unspecified
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unspecified: "siri.messages.unspecified"
    ]
}

@AppEnum(schema: .messages.messageAttribute)
enum ChatMessageAttribute: String {
    case unspecified
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unspecified: "siri.messages.unspecified"
    ]
}

@AppEnum(schema: .messages.messageType)
enum ChatMessageType: String {
    case unspecified
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unspecified: "siri.messages.unspecified"
    ]
}

@AppEntity(schema: .messages.message)
struct ChatMessageEntity: IndexedEntity, OwnershipProvidingEntity {
    static let defaultQuery = ChatMessageQuery()
    let id: UUID
    var messageType: ChatMessageType
    var author: ChatPersonEntity
    var isRead: Bool
    var attributes: Set<ChatMessageAttribute>
    var conversation: ChatConversationEntity
    var date: Date
    var body: AttributedString?
    var subject: AttributedString?
    var attachments: [IntentFile]
    var audioMessage: IntentFile?
    var customAttachments: [ChatCustomAttachment]
    var locations: [PlaceDescriptor]
    var links: [LinkMetadata]
    var messageEffect: ChatMessageEffect?
    var reaction: ChatReadReaction?
    var referencedMessage: ChatMessageEntity?
    var notificationIdentifier: String?
    var ownership: EntityOwnership { .shared }
    var displayRepresentation: DisplayRepresentation {
        let title = body.map { String($0.characters) }?.trimmedNonEmpty ?? String(localized: .siriMessagesMessage)
        let sentAt = date.formatted(date: .abbreviated, time: .shortened)
        return .init(title: "\(title)", subtitle: "\(author.name) · \(sentAt)")
    }

    init(
        id: UUID, author: ChatPersonEntity, isRead: Bool, conversation: ChatConversationEntity,
        date: Date, body: AttributedString?
    ) {
        self.id = id
        messageType = .unspecified
        self.author = author
        self.isRead = isRead
        attributes = []
        self.conversation = conversation
        self.date = date
        self.body = body
        subject = nil
        attachments = []
        audioMessage = nil
        customAttachments = []
        locations = []
        links = []
        messageEffect = nil
        reaction = nil
        referencedMessage = nil
        notificationIdentifier = nil
    }
}

@AppEntity(schema: .messages.customAttachment)
struct ChatCustomAttachment {
    let id: String
    var sourceName: AttributedString?
    var description: AttributedString?
    static let defaultQuery = ChatCustomAttachmentQuery()
    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(description ?? AttributedString())")
    }
}

struct ChatCustomAttachmentQuery: EntityQuery {
    func entities(for identifiers: [String]) throws -> [ChatCustomAttachment] { [] }
}

@AppEnum(schema: .messages.messageEffect)
enum ChatMessageEffect: String {
    case unspecified
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unspecified: "siri.messages.unspecified"
    ]
}

@UnionValue
enum ChatReadReaction {
    case attributedString(AttributedString)
    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "siri.messages.emoji")
    nonisolated static let caseDisplayRepresentations: [Cases: DisplayRepresentation] = [
        .attributedString: "siri.messages.emoji"
    ]
}
