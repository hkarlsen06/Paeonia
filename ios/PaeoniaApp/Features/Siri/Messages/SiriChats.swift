import AppIntents
import Foundation

@MainActor
enum SiriChats {
    struct Snapshot {
        var conversations: [ChatConversationEntity] = []
        var messages: [ChatMessageEntity] = []
    }

    static func people(_ couple: SiriCouple) -> [ChatPersonEntity] {
        var people = [
            ChatPersonEntity(
                id: couple.ownerUserID, name: String(localized: .chatsCoupleChatYou), isMe: true)
        ]
        if let id = couple.partnerUserID {
            people.append(ChatPersonEntity(id: id, name: couple.partnerName, isMe: false))
        }
        return people
    }

    static func snapshot() async -> Snapshot {
        guard let couple = await SiriAppContext.shared.access().couple else { return Snapshot() }
        return await snapshot(for: couple)
    }

    static func snapshot(for couple: SiriCouple) async -> Snapshot {
        let service = ThreadChatServiceFactory.makeDefault()
        let summaries = await service.cachedThreadSummaries(ownerUserID: couple.ownerUserID)
            .filter { $0.coupleID == couple.coupleID }
        let marks = await service.chatReadMarks(ownerUserID: couple.ownerUserID)
        let memories = await SiriContent.memories(for: couple)
        let stories = await FileStoriesCache.shared.snapshot(ownerUserID: couple.ownerUserID).stories
        let people = people(couple)
        var result = Snapshot()
        var subjects = summaries.map(\.subject)
        if !subjects.contains(.couple) { subjects.append(.couple) }
        for subject in subjects {
            let summary = summaries.first { $0.subject == subject }
            guard
                let title = await title(
                    for: subject, couple: couple, service: service,
                    memories: memories, stories: stories)
            else { continue }
            let readThrough = summary.flatMap { $0.latestReadCursor(onThisPhone: marks[$0.threadID]) }
            let conversation = ChatConversationEntity(
                id: subject.id, subject: subject, threadID: summary?.threadID,
                recipients: people, displayName: title,
                previewText: AttributedString(summary?.lastMessagePreview ?? ""),
                conversationName: title,
                isRead:
                    !(summary?.isUnread(
                        by: couple.ownerUserID,
                        readThrough: readThrough) ?? false),
                dateLastActive: summary?.lastMessageAt
            )
            result.conversations.append(conversation)
            result.messages += await messages(
                in: conversation, couple: couple, service: service, summary: summary,
                readThrough: readThrough)
        }
        return result
    }

    private static func messages(
        in conversation: ChatConversationEntity, couple: SiriCouple,
        service: any ThreadChatServicing, summary: ThreadChatSummary?, readThrough: ThreadChatMessageCursor?
    ) async -> [ChatMessageEntity] {
        var entities: [ChatMessageEntity] = []
        let cached = await service.cachedMessages(
            ownerUserID: couple.ownerUserID, subjectID: conversation.subject.id)
        var remote = cached
        if let summary, let latest = latestMessage(in: summary), !cached.contains(where: { $0.id == latest.id }) {
            remote.append(latest)
        }
        let pending = await service.pendingMessages(
            ownerUserID: couple.ownerUserID, coupleID: couple.coupleID, subjectID: conversation.subject.id)
        let linked = ThreadChatMessage.claimingPending(remote: remote, cached: cached, pending: pending)
        for message in ThreadChatMessage.visibleOrdered(remote: linked, optimistic: pending)
        where !message.isDeleted {
            guard let author = conversation.recipients.first(where: { $0.id == message.senderUserID }) else { continue }
            let cursor = ThreadChatMessageCursor(createdAt: message.createdAt, messageID: message.id)
            let read =
                message.senderUserID == couple.ownerUserID
                || readThrough.map { $0 >= cursor } == true
            entities.append(
                ChatMessageEntity(
                    id: message.id, author: author, isRead: read,
                    conversation: conversation, date: message.createdAt,
                    body: AttributedString(message.body)))
        }
        return entities
    }

    /// A chat summary already holds its newest message, even before that chat has been opened.
    private static func latestMessage(in summary: ThreadChatSummary) -> ThreadChatMessage? {
        guard let id = summary.lastMessageID, let date = summary.lastMessageAt,
            let sender = summary.lastMessageSenderUserID
        else { return nil }
        return ThreadChatMessage(
            id: id, threadID: summary.threadID, subjectID: summary.subject.id,
            senderUserID: sender, body: summary.lastMessageBody ?? "", createdAt: date,
            clientOperationID: nil, isSending: false)
    }

    private static func title(
        for subject: ThreadChatSubject, couple: SiriCouple,
        service: any ThreadChatServicing, memories: [MemoryRecord], stories: [Story]
    ) async -> String? {
        switch subject {
        case .couple: return String(localized: .chatsCoupleChatTitle)
        case .memory(let id):
            guard let memory = memories.first(where: { $0.snapshot.memoryID == id }) else { return nil }
            return memory.snapshot.title ?? String(localized: .siriMessagesConversation)
        case .story(let id):
            guard let story = stories.first(where: { $0.id == id }) else { return nil }
            return story.caption ?? String(localized: .siriMessagesConversation)
        case .question:
            return await questionTitle(subject.id, couple: couple, service: service)
        case .game(let game): return String(localized: game.kind.name)
        }
    }

    private static func questionTitle(_ id: UUID, couple: SiriCouple, service: any ThreadChatServicing) async -> String
    {
        let rounds = await service.cachedRounds(ownerUserID: couple.ownerUserID, questionID: id)
        let current = FileDailyChallengeSnapshotCache().load(ownerUserID: couple.ownerUserID)?
            .loadResult(currentUserID: couple.ownerUserID).snapshot.questions
            .first { $0.questionID == id && $0.coupleID == couple.coupleID }
        if let question = rounds?.rounds().last(where: { $0.coupleID == couple.coupleID }) ?? current {
            return question.prompt
        }
        let topics = await FileTopicsCache.shared.document(ownerUserID: couple.ownerUserID)
        if let question = topics.details.values.flatMap(\.questions).first(where: { $0.questionID == id }) {
            return Locale.current.prefersNorwegianTopicCopy ? question.promptNB : question.promptEN
        }
        return String(localized: .siriMessagesConversation)
    }

    static func resolve(_ entity: ChatMessageEntity, couple: SiriCouple) async throws
        -> ThreadChatMessage
    {
        let snapshot = await snapshot(for: couple)
        guard let current = snapshot.messages.first(where: { $0.id == entity.id }) else {
            throw SiriFailure(.siriMessagesUnavailable)
        }
        let service = ThreadChatServiceFactory.makeDefault()
        let cached = await service.cachedMessages(
            ownerUserID: couple.ownerUserID,
            subjectID: current.conversation.subject.id)
        let pending = await service.pendingMessages(
            ownerUserID: couple.ownerUserID,
            coupleID: couple.coupleID, subjectID: current.conversation.subject.id)
        guard
            let message = ThreadChatMessage.visibleOrdered(remote: cached, optimistic: pending)
                .first(where: { $0.id == entity.id && !$0.isDeleted })
        else {
            guard !cached.contains(where: { $0.id == entity.id && $0.isDeleted }) else {
                throw SiriFailure(.siriMessagesUnavailable)
            }
            let summaries = await service.cachedThreadSummaries(ownerUserID: couple.ownerUserID)
            guard
                let summary = summaries.first(where: { $0.coupleID == couple.coupleID && $0.lastMessageID == entity.id }
                ),
                let latest = latestMessage(in: summary)
            else { throw SiriFailure(.siriMessagesUnavailable) }
            return latest
        }
        return message
    }
    static func write<Value>(_ action: () async throws -> Value) async throws -> Value {
        do { return try await action() } catch let failure as SiriFailure { throw failure } catch {
            throw SiriFailure(PaeoniaFailure(error) == .offline ? .siriMessagesOffline : .siriMessagesTryAgain)
        }
    }

}
