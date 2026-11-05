import AppIntents
import CoreSpotlight
import Foundation

/// One memory, as the photos schema's album: its title is the album name and its date the
/// creation date. Visible notes are searchable text in Spotlight.
@AppEntity(schema: .photos.album)
struct MemoryAlbumEntity: IndexedEntity, OwnershipProvidingEntity {
    @available(iOS 27.3, *)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let defaultQuery = MemoryAlbumQuery()

    /// The memory id.
    let id: UUID
    var name: String
    var creationDate: Date?
    var albumType: MemoryAlbumKind
    let placeName: String?
    let notes: String

    var searchableAttributes: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = name
        attributes.textContent = notes
        return attributes
    }

    var ownership: EntityOwnership { .shared }

    var displayRepresentation: DisplayRepresentation {
        let day = creationDate?.formatted(date: .long, time: .omitted)
        let subtitle = [day, placeName].compactMap(\.self).joined(separator: " · ")
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "photo.on.rectangle.angled")
        )
    }

    init(record: MemoryRecord) {
        id = record.snapshot.memoryID
        placeName = record.snapshot.place?.nameAndCity
        notes = [record.snapshot.ownNote?.visibleBody, record.snapshot.partnerNote?.visibleBody]
            .compactMap(\.self).joined(separator: "\n")
        name = record.snapshot.title ?? ""
        creationDate = MemoryTimeline.pickerDate(forLocalDate: record.snapshot.memoryDate)
        albumType = .memory
    }
}

struct MemoryAlbumQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MemoryAlbumEntity] {
        await SiriContent.memories()
            .filter { identifiers.contains($0.snapshot.memoryID) }
            .map(MemoryAlbumEntity.init)
    }

    func entities(matching string: String) async throws -> [MemoryAlbumEntity] {
        await SiriContent.memories()
            .filter { ($0.snapshot.title ?? "").localizedStandardContains(string) }
            .map(MemoryAlbumEntity.init)
    }

    /// The newest few.
    func suggestedEntities() async throws -> [MemoryAlbumEntity] {
        await SiriContent.memories().prefix(5).map(MemoryAlbumEntity.init)
    }

    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
}

@AppEnum(schema: .photos.albumType)
enum MemoryAlbumKind: String {
    case memory

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .memory: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.memories.albumType.memory",
                table: "Localizable",
                comment: "Siri: the kind of photo album Paeonia has, a memory the couple made."
            )
        ),
    ]
}
