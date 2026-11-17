import Foundation

nonisolated enum MemoryMediaPurpose: String, Codable, Sendable, Equatable {
    case photo = "memory_photo"
    case voice = "voice_note"
    /// A story photo. It goes through the same upload as a memory photo.
    case story = "story_photo"
    /// A Guess my spot photo, stripped of its metadata before upload.
    case guessMySpot = "guess_my_spot_photo"
    /// The photo in a letter. Only the author reads it until the partner opens the letter.
    case letter = "letter_image"

    /// A memory's or a story's file is a video when its MIME type says so.
    func mediaType(for mimeType: String) -> String {
        switch self {
        case .photo, .story:
            MediaUpload.isVideo(mimeType: mimeType) ? "video" : "image"
        case .guessMySpot, .letter:
            "image"
        case .voice:
            "voice"
        }
    }

    /// What the upload is reserved for. A story photo belongs to its story, a letter's
    /// photo to its letter, and a Guess my spot photo to its round.
    var reservedParentKind: String {
        switch self {
        case .photo, .voice:
            "memory_media"
        case .story:
            "story"
        case .guessMySpot:
            "guess_my_spot_round"
        case .letter:
            "letter"
        }
    }
}

nonisolated struct MemoryUploadMedia: Sendable, Equatable {
    let data: Data
    let purpose: MemoryMediaPurpose
    let mimeType: String
    let fileExtension: String
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let accessibilityText: String?
    /// The id the asset gets. Nil lets the server choose.
    let mediaAssetID: UUID?

    init(
        data: Data,
        purpose: MemoryMediaPurpose,
        mimeType: String,
        fileExtension: String,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil,
        accessibilityText: String? = nil,
        mediaAssetID: UUID? = nil
    ) {
        self.data = data
        self.purpose = purpose
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.accessibilityText = accessibilityText
        self.mediaAssetID = mediaAssetID
    }
}

nonisolated extension MemoryUploadMedia {
    /// Maps the prepared file instead of reading it into memory.
    init(video: PreparedVideo, purpose: MemoryMediaPurpose, accessibilityText: String? = nil) throws {
        try self.init(
            data: Data(contentsOf: video.fileURL, options: .mappedIfSafe),
            purpose: purpose,
            mimeType: MediaUpload.videoMimeType,
            fileExtension: MediaUpload.videoFileExtension,
            width: video.width,
            height: video.height,
            durationMs: video.durationMs,
            accessibilityText: accessibilityText
        )
    }
}

nonisolated struct MemoryMediaUploadResult: Equatable, Sendable {
    let memoryMediaID: UUID
    let mediaAssetID: UUID

    func optimisticSnapshot(
        ownerUserID: UUID,
        kind: MemoryMediaKind = .image,
        durationMs: Int? = nil,
        sortOrder: Int,
        updatedAt: Date = Date(),
        accessibilityText: String? = nil
    ) -> MemoryMediaSnapshot {
        MemoryMediaSnapshot(
            memoryMediaID: memoryMediaID,
            mediaAssetID: mediaAssetID,
            ownerUserID: ownerUserID,
            kind: kind,
            durationMs: durationMs,
            sortOrder: sortOrder,
            updatedAt: updatedAt,
            accessibilityText: accessibilityText
        )
    }
}

nonisolated protocol MemoryMediaUploading: Sendable {
    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult
}

nonisolated struct LiveMemoryMediaUploadService: MemoryMediaUploading {
    private let uploader: MediaUploader
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        uploader = MediaUploader(client: client)
        self.isSignedIn = isSignedIn
    }

    static func live() throws -> LiveMemoryMediaUploadService {
        LiveMemoryMediaUploadService(client: try PaeoniaConvexClientProvider.shared.client())
    }

    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult {
        try await PaeoniaSignedIn.require(isSignedIn)
        let mediaAssetID = try await uploader.upload(
            media.data,
            as: MediaUpload(
                parentKind: media.purpose.reservedParentKind,
                parentID: memoryMediaID,
                purpose: media.purpose.rawValue,
                mediaType: media.purpose.mediaType(for: media.mimeType),
                mimeType: media.mimeType,
                fileExtension: media.fileExtension,
                coupleID: coupleID,
                accessibilityText: media.accessibilityText,
                width: media.width,
                height: media.height,
                durationMs: media.durationMs,
                mediaAssetID: media.mediaAssetID
            ),
            reserveOperation: reserveOperation,
            finalizeOperation: finalizeOperation
        )
        return MemoryMediaUploadResult(memoryMediaID: memoryMediaID, mediaAssetID: mediaAssetID)
    }
}
