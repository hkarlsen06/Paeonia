import AppIntents
import CoreSpotlight
import Foundation

struct ChatPersonQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ChatPersonEntity] {
        await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ChatPersonEntity] {
        await suggestedEntities().filter { $0.name.localizedStandardContains(string) }
    }
    func suggestedEntities() async -> [ChatPersonEntity] {
        guard let couple = await SiriAppContext.shared.access().couple else { return [] }
        return await SiriChats.people(couple)
    }
    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription)
        async throws
    {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
}

struct ChatConversationQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ChatConversationEntity] {
        await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ChatConversationEntity] {
        await suggestedEntities().filter { $0.displayName.localizedStandardContains(string) }
    }
    func suggestedEntities() async -> [ChatConversationEntity] {
        await SiriChats.snapshot().conversations
    }
    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription)
        async throws
    {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
}

struct ChatMessageQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ChatMessageEntity] {
        await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ChatMessageEntity] {
        await suggestedEntities().filter {
            String(($0.body ?? AttributedString()).characters).localizedStandardContains(string)
        }
    }
    func suggestedEntities() async -> [ChatMessageEntity] { await SiriChats.snapshot().messages }
    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription)
        async throws
    {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
}
