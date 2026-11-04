import AppIntents
import CoreLocation
import CoreSpotlight
import CoreTransferable
import Foundation
import GeoToolbox
import UniformTypeIdentifiers

nonisolated enum MemoryPhotoID: Hashable, Sendable, EntityIdentifierConvertible {
    /// A photo in a memory, by its media asset id.
    case saved(mediaAssetID: UUID)
    /// A photo from another app that is not in a memory yet. It waits in `MemoryPhotoInbox`.
    case incoming(UUID)

    var entityIdentifierString: String {
        switch self {
        case let .saved(id): "photo:\(id.uuidString)"
        case let .incoming(id): "incoming:\(id.uuidString)"
        }
    }

    static func entityIdentifier(for entityIdentifierString: String) -> MemoryPhotoID? {
        let parts = entityIdentifierString.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "photo": return .saved(mediaAssetID: id)
        case "incoming": return .incoming(id)
        default: return nil
        }
    }
}

/// One photo in a memory, as the photos schema's asset. Siri can send it to another app as a
/// JPEG, and a photo from another app can come in as an incoming photo that Paeonia adds to a
/// memory. Both directions check access and App Lock first.
@AppEntity(schema: .photos.asset)
struct MemoryPhotoEntity: IndexedEntity, OwnershipProvidingEntity {
    static let defaultQuery = MemoryPhotoQuery()

    let id: MemoryPhotoID
    var creationDate: Date?
    var location: PlaceDescriptor?
    var assetType: MemoryPhotoKind?
    var isFavorite: Bool
    var isHidden: Bool
    var hasSuggestedEdits: Bool
    // Paeonia shows photos as they were taken and edits none, so these stay empty.
    var aperture: Double?
    var exposure: Double?
    var saturation: Double?
    var warmth: Double?
    var filter: MemoryPhotoFilter?
    var isPortraitModeEnabled: Bool?
    /// The memory it is in. Nil for an incoming photo.
    let memoryID: UUID?
    let memoryTitle: String?
    /// What the person wrote about the photo, for VoiceOver.
    let photoDescription: String?

    var ownership: EntityOwnership { .shared }

    var displayRepresentation: DisplayRepresentation {
        guard let memoryTitle else {
            return DisplayRepresentation(
                title: "\(String(localized: .siriPhotosIncomingTitle))",
                image: .init(systemName: "photo.badge.plus")
            )
        }
        // A described photo shows its description over the memory's title, otherwise the title
        // over the day.
        let subtitle = photoDescription == nil
            ? creationDate?.formatted(date: .long, time: .omitted) ?? ""
            : memoryTitle
        return DisplayRepresentation(
            title: "\(photoDescription ?? memoryTitle)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "photo")
        )
    }

    init(media: MemoryMediaSnapshot, in record: MemoryRecord) {
        id = .saved(mediaAssetID: media.mediaAssetID)
        memoryID = record.snapshot.memoryID
        memoryTitle = record.snapshot.title ?? ""
        photoDescription = media.accessibilityText?.trimmedNonEmpty
        creationDate = MemoryTimeline.pickerDate(forLocalDate: record.snapshot.memoryDate)
        location = record.snapshot.place.map(Self.descriptor)
        assetType = .photo
        isFavorite = false
        isHidden = false
        hasSuggestedEdits = false
        aperture = nil
        exposure = nil
        saturation = nil
        warmth = nil
        filter = .original
        isPortraitModeEnabled = nil
    }

    init(incoming id: UUID) {
        self.id = .incoming(id)
        memoryID = nil
        memoryTitle = nil
        photoDescription = nil
        creationDate = nil
        location = nil
        assetType = .photo
        isFavorite = false
        isHidden = false
        hasSuggestedEdits = false
        aperture = nil
        exposure = nil
        saturation = nil
        warmth = nil
        filter = .original
        isPortraitModeEnabled = nil
    }

    /// The visible photos of `records`, in each memory's order.
    static func all(in records: [MemoryRecord]) -> [MemoryPhotoEntity] {
        records.flatMap { record in
            record.snapshot.media
                .filter(\.isVisible)
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { MemoryPhotoEntity(media: $0, in: record) }
        }
    }

    private static func descriptor(for place: MemoryPlace) -> PlaceDescriptor {
        PlaceDescriptor(
            representations: [
                .coordinate(CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)),
            ],
            commonName: place.name
        )
    }

    /// The photo's bytes: the memory photo from the local cache (downloaded once if needed),
    /// or the incoming file. Refused without access or while App Lock is locked.
    @MainActor
    func imageData() async throws -> Data {
        guard await SiriAppContext.shared.access().couple != nil else {
            throw SiriFailure(.siriAccessSignedOut)
        }
        let lock = AppLockModel.shared
        guard !lock.isEnabled || !lock.isLocked else { throw SiriFailure(.siriAppLockStillLocked) }
        let data: Data? = switch id {
        case let .saved(mediaAssetID): await MemoryMediaImageProviderFactory.shared?.imageData(for: mediaAssetID)
        case let .incoming(id): MemoryPhotoInbox.data(for: id)
        }
        guard let data else { throw SiriFailure(.siriPhotosUnavailable) }
        return data
    }
}

extension MemoryPhotoEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            try await photo.imageData()
        }
        FileRepresentation(importedContentType: .image) { received in
            MemoryPhotoEntity(incoming: try MemoryPhotoInbox.add(fileAt: received.file))
        }
    }
}

struct MemoryPhotoQuery: IndexedEntityQuery {
    func entities(for identifiers: [MemoryPhotoID]) async throws -> [MemoryPhotoEntity] {
        let saved = await SiriContent.photos().filter { identifiers.contains($0.id) }
        let incoming = identifiers.compactMap { id -> MemoryPhotoEntity? in
            guard case let .incoming(id) = id, MemoryPhotoInbox.contains(id) else { return nil }
            return MemoryPhotoEntity(incoming: id)
        }
        return saved + incoming
    }

    /// The photos of the newest memory.
    func suggestedEntities() async throws -> [MemoryPhotoEntity] {
        guard let newest = await SiriContent.memories().first else { return [] }
        return MemoryPhotoEntity.all(in: [newest])
    }

    func reindexEntities(
        for identifiers: [MemoryPhotoID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await SiriEntityIndexer.shared.refresh(force: true)
    }
}

@AppEnum(schema: .photos.assetType)
enum MemoryPhotoKind: String {
    case photo

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .photo: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.memories.assetType.photo",
                table: "Localizable",
                comment: "Siri: the kind of item in a memory, a photo."
            )
        ),
    ]
}

@AppEnum(schema: .photos.filterType)
enum MemoryPhotoFilter: String {
    case original

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .original: DisplayRepresentation(
            title: LocalizedStringResource(
                "siri.memories.filter.original",
                table: "Localizable",
                comment: "Siri: a photo's filter when it has none, so it looks as it was taken."
            )
        ),
    ]
}
