import Foundation
#if DEBUG
import OSLog
#endif

/// A photo or video of a memory saved on this phone, which the queued create or attach sends
/// before the memory names it. The asset id is chosen here, so the saved memory shows the
/// photo from the local caches before it uploads. The fixed operations make a retry pick up
/// the same upload instead of sending it twice.
nonisolated struct MemoryQueuedUpload: Codable, Equatable, Sendable {
    enum Local: Codable, Equatable, Sendable {
        /// A compressed photo, kept in the queued write.
        case photo(Data, mimeType: String, fileExtension: String)
        /// A prepared video, by its file name in `MemoryDraftMedia.videoDirectoryURL()`.
        case video(fileName: String)
    }

    let mediaAssetID: UUID
    let memoryMediaID: UUID
    let coupleID: UUID
    let local: Local
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let accessibilityText: String
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation

    var videoFileURL: URL? {
        guard case let .video(fileName) = local else { return nil }
        return MemoryDraftMedia.videoDirectoryURL().appendingPathComponent(fileName)
    }

    var byteCount: Int64 {
        switch local {
        case let .photo(data, _, _):
            Int64(data.count)
        case .video:
            videoFileURL.flatMap {
                (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.size] as? NSNumber
            }?.int64Value ?? 0
        }
    }
}

nonisolated enum MemoryQueuedUploads {
    #if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app", category: "Memories"
    )
    #endif

    /// Sends each upload in order. A video whose file is gone from this phone is skipped, since
    /// nothing can send it any more. Upload errors throw, so the queued write retries later.
    static func send(
        _ uploads: [MemoryQueuedUpload],
        with uploader: (any MemoryMediaUploading)?
    ) async throws {
        guard !uploads.isEmpty else { return }
        guard let uploader else { throw MemoryQueuedUploadError.unavailable }
        for upload in uploads {
            guard let media = try uploadMedia(for: upload) else {
                #if DEBUG
                logger.error("A queued memory video is no longer on this phone")
                #endif
                continue
            }
            _ = try await uploader.uploadMedia(
                media,
                memoryMediaID: upload.memoryMediaID,
                coupleID: upload.coupleID,
                reserveOperation: upload.reserveOperation,
                finalizeOperation: upload.finalizeOperation
            )
        }
    }

    /// A send that uploads grows its time limit with the bytes, so a long video can finish on a
    /// slow connection.
    static func timeLimit(for uploads: [MemoryQueuedUpload]) -> Duration? {
        guard !uploads.isEmpty else { return nil }
        return UploadTimeLimit.forUploading(uploads.reduce(0) { $0 + $1.byteCount })
    }

    /// Deletes the sent videos' files. The video cache already holds their copies.
    static func deleteFiles(of uploads: [MemoryQueuedUpload]) {
        for url in uploads.compactMap(\.videoFileURL) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The queued uploads of a create or attach write, for the handlers and the outgoing media sweep.
    static func uploads(in operation: PendingSyncOperationSnapshot) -> [MemoryQueuedUpload] {
        guard let data = operation.requestData else { return [] }
        let decoder = JSONDecoder()
        switch operation.operationKind {
        case .createMemory:
            return (try? decoder.decode(CreateMemoryOperationPayload.self, from: data))?.uploads ?? []
        case .attachMemoryMedia:
            return (try? decoder.decode(AttachMemoryMediaOperationPayload.self, from: data))?.uploads ?? []
        default:
            return []
        }
    }

    private static func uploadMedia(for upload: MemoryQueuedUpload) throws -> MemoryUploadMedia? {
        let data: Data
        let mimeType: String
        let fileExtension: String
        switch upload.local {
        case let .photo(bytes, photoMimeType, photoFileExtension):
            (data, mimeType, fileExtension) = (bytes, photoMimeType, photoFileExtension)
        case .video:
            guard let url = upload.videoFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
            data = try Data(contentsOf: url, options: .mappedIfSafe)
            (mimeType, fileExtension) = (MediaUpload.videoMimeType, MediaUpload.videoFileExtension)
        }
        return MemoryUploadMedia(
            data: data,
            purpose: .photo,
            mimeType: mimeType,
            fileExtension: fileExtension,
            width: upload.width,
            height: upload.height,
            durationMs: upload.durationMs,
            accessibilityText: upload.accessibilityText,
            mediaAssetID: upload.mediaAssetID
        )
    }
}

nonisolated enum MemoryQueuedUploadError: Error {
    /// This build has no backend to upload to.
    case unavailable
}
