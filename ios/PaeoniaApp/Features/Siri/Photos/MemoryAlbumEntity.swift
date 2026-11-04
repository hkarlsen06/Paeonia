import AppIntents
import CoreSpotlight
import Foundation

/// One memory, as the photos schema's album: its title is the album name and its date the
/// creation date. Notes stay out, because the SDK cannot ask for Face ID per property.
@AppEntity(schema: .photos.album)
struct MemoryAlbumEntity: IndexedEntity, OwnershipProvidingEntity {
    static let defaultQuery = MemoryAlbumQuery()

    /// The memory id.
    let id: UUID
    var name: String
    var creationDate: Date?
    var albumType: MemoryAlbumKind
    let placeName: String?

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
