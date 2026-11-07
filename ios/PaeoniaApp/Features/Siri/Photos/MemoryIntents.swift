import AppIntents
import Foundation
import UIKit

/// "Open our Bergen memory."
@AppIntent(schema: .photos.openAlbum)
struct OpenMemoryIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var target: MemoryAlbumEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if await coupleToOpenFor() != nil {
            SiriAppContext.shared.open(.memory(memoryID: target.id, showsComments: false))
        }
        return .result()
    }
}

/// Opens the memory on that photo. An incoming photo opens the new-memory form with it. The
/// photos schema's own open intent is deprecated in favor of the system one.
@AppIntent(schema: .system.open)
struct OpenMemoryPhotoIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var target: MemoryPhotoEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await coupleToOpenFor() != nil else { return .result() }
        switch target.id {
        case let .saved(mediaAssetID):
            if let memoryID = target.memoryID {
                SiriAppContext.shared.open(.memoryPhoto(memoryID: memoryID, mediaAssetID: mediaAssetID))
            }
        case let .incoming(id):
            SiriAppContext.shared.open(.newMemory(photoIDs: [id]))
        }
        return .result()
    }
}

/// Photos from another app become a new memory. A memory needs a title, so this opens the
/// new-memory form with the photos in it, and the person names and saves it.
@AppIntent(schema: .photos.createAssets)
struct CreateMemoryFromPhotosIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var files: [IntentFile]

    @MainActor
    func perform() async throws -> some ReturnsValue<[MemoryPhotoEntity]> {
        _ = try await coupleToActFor()
        guard !files.isEmpty else { throw SiriFailure(.siriPhotosNoneToAdd) }
        guard files.count <= MemoryEditorPhotosField.maxPhotosPerPartner else {
            throw SiriFailure(.siriPhotosTooMany(MemoryEditorPhotosField.maxPhotosPerPartner.formatted()))
        }
        let photos = files.map(\.data)
        guard photos.allSatisfy({ UIImage(data: $0) != nil }) else { throw SiriFailure(.siriPhotosUnreadable) }
        let ids = try photos.map(MemoryPhotoInbox.add)
        try await continueInForeground(IntentDialog(.siriPhotosNameTheMemory), alwaysConfirm: false)
        SiriAppContext.shared.open(.newMemory(photoIDs: ids))
        return .result(value: ids.map { MemoryPhotoEntity(incoming: $0) })
    }
}

/// Renames a memory.
@AppIntent(schema: .photos.updateAlbum)
struct RenameMemoryIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var target: MemoryAlbumEntity
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let writes = await MemoryWrites(couple: try await coupleToActFor())
        try await writes.rename(target.id, to: name)
        return .result()
    }
}

/// Deletes memories for both partners, like Delete on the memory.
@AppIntent(schema: .photos.deleteAlbum)
struct DeleteMemoriesIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var entities: [MemoryAlbumEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        let writes = await MemoryWrites(couple: try await coupleToActFor())
        for memory in entities {
            try await writes.delete(memory.id)
        }
        return .result()
    }
}

/// Adds photos to a memory: photos from other memories, or photos from another app.
@AppIntent(schema: .photos.addAssetsToAlbum)
struct AddPhotosToMemoryIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var assets: [MemoryPhotoEntity]
    var album: MemoryAlbumEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let writes = await MemoryWrites(couple: try await coupleToActFor())
        var photos: [Data] = []
        for asset in assets {
            photos.append(try await asset.imageData())
        }
        try await writes.addPhotos(photos, to: album.id)
        let incoming = assets.compactMap { asset -> UUID? in
            if case let .incoming(id) = asset.id { id } else { nil }
        }
        _ = MemoryPhotoInbox.take(incoming)
        return .result()
    }
}

/// Takes photos out of a memory.
@AppIntent(schema: .photos.removeAssetsFromAlbum)
struct RemovePhotosFromMemoryIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var assets: [MemoryPhotoEntity]
    var album: MemoryAlbumEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let writes = await MemoryWrites(couple: try await coupleToActFor())
        try await writes.removePhotos(Set(assets.compactMap(\.mediaAssetID)), from: album.id)
        return .result()
    }
}

/// Deletes photos, which takes each out of its memory.
@AppIntent(schema: .photos.deleteAssets)
struct DeleteMemoryPhotosIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    var entities: [MemoryPhotoEntity]

    @MainActor
    func perform() async throws -> some IntentResult {
        let writes = await MemoryWrites(couple: try await coupleToActFor())
        let byMemory = Dictionary(grouping: entities.filter { $0.mediaAssetID != nil }) { $0.memoryID }
        for (memoryID, photos) in byMemory {
            guard let memoryID else { continue }
            try await writes.removePhotos(Set(photos.compactMap(\.mediaAssetID)), from: memoryID)
        }
        return .result()
    }
}

extension MemoryPhotoEntity {
    /// Nil for an incoming photo.
    var mediaAssetID: UUID? {
        if case let .saved(mediaAssetID) = id { mediaAssetID } else { nil }
    }
}

/// Memory changes through `MemoriesViewModel`, the same local-first path as the edit form
/// and Delete: each change is queued and sent the way the form's save is.
struct MemoryWrites {
    private let model = MemoriesViewModel()
    private let ownerUserID: UUID

    init(couple: SiriCouple) async {
        ownerUserID = couple.ownerUserID
        model.setLocalChangeSyncHandler { await SiriAppContext.shared.syncAfterLocalChange() }
        await model.configure(currentUserID: couple.ownerUserID, coupleID: couple.coupleID)
    }

    func rename(_ memoryID: UUID, to name: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SiriFailure(.siriMemoriesNameMissing) }
        let record = try record(memoryID)
        try check((await model.saveEdits(edit(record, title: name))).isSaved)
    }

    func addPhotos(_ photos: [Data], to memoryID: UUID) async throws {
        guard !photos.isEmpty else { throw SiriFailure(.siriPhotosNoneToAdd) }
        let record = try record(memoryID)
        let own = record.snapshot.media.filter { $0.isVisible && $0.ownerUserID == ownerUserID }.count
        let limit = MemoryEditorPhotosField.maxPhotosPerPartner
        guard own + photos.count <= limit else { throw SiriFailure(.siriPhotosTooMany(limit.formatted())) }
        guard model.canAttachPhotos else { throw SiriFailure(MemoriesNotice.photoUploadFailed.message) }
        try check((await model.saveEdits(edit(record, newPhotos: photos))).isSaved)
    }

    func removePhotos(_ mediaAssetIDs: Set<UUID>, from memoryID: UUID) async throws {
        let record = try record(memoryID)
        let media = record.snapshot.media.filter { $0.isVisible && mediaAssetIDs.contains($0.mediaAssetID) }
        guard !mediaAssetIDs.isEmpty, media.count == mediaAssetIDs.count else {
            throw SiriFailure(.siriPhotosNotInMemory)
        }
        try check((await model.saveEdits(edit(record, removedMedia: media))).isSaved)
    }

    func delete(_ memoryID: UUID) async throws {
        await model.deleteMemory(try record(memoryID))
        if let notice = model.notice {
            throw SiriFailure(notice.message)
        }
    }

    private func record(_ memoryID: UUID) throws -> MemoryRecord {
        guard let record = model.record(for: memoryID) else { throw SiriFailure(.siriMemoriesGone) }
        return record
    }

    /// An edit that changes only what is passed. Note and place stay as they are.
    private func edit(
        _ record: MemoryRecord,
        title: String? = nil,
        newPhotos: [Data] = [],
        removedMedia: [MemoryMediaSnapshot] = []
    ) -> MemoryEdit {
        MemoryEdit(
            base: record,
            title: title ?? record.snapshot.title ?? "",
            date: record.snapshot.memoryDate,
            note: "",
            newPhotos: newPhotos,
            removedMedia: removedMedia,
            place: record.snapshot.place
        )
    }

    private func check(_ saved: Bool) throws {
        guard !saved else { return }
        throw SiriFailure((model.notice ?? .editFailed).message)
    }
}
