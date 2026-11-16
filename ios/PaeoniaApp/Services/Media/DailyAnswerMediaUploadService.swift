import Foundation

/// What kind of daily-answer media is being uploaded. Drives the backend
/// `upload_purpose` and `media_type`; both kinds share the `daily_answer_media`
/// reserved parent so they attach to the same answer.
nonisolated enum DailyAnswerMediaPurpose: String, Codable, Sendable, Equatable {
    case photo = "daily_answer_media"
    case voice = "voice_note"
    /// A photo, a GIF or a video in a question chat message.
    case threadPhoto = "thread_media"

    /// A chat message's file is a video when its MIME type says so.
    func mediaType(for mimeType: String) -> String {
        switch self {
        case .photo:
            "image"
        case .threadPhoto:
            MediaUpload.isVideo(mimeType: mimeType) ? "video" : "image"
        case .voice:
            "voice"
        }
    }
}

/// A staged media file ready to upload as part of an answer.
nonisolated struct DailyAnswerUploadMedia: Sendable, Equatable {
    let data: Data
    let purpose: DailyAnswerMediaPurpose
    let mimeType: String
    let fileExtension: String
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let accessibilityText: String?

    init(
        data: Data,
        purpose: DailyAnswerMediaPurpose,
        mimeType: String,
        fileExtension: String,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil,
        accessibilityText: String? = nil
    ) {
        self.data = data
        self.purpose = purpose
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.accessibilityText = accessibilityText
    }
}

nonisolated protocol DailyAnswerMediaUploading: Sendable {
    /// Reserves, uploads the bytes, and finalizes one media asset against an answer,
    /// returning its media asset id. The two operations make the reserve and finalize
    /// calls idempotent so a retried upload can't create duplicate assets.
    func uploadMedia(
        _ media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID

    /// The media asset an earlier `uploadMedia` with the same reserve operation finished,
    /// or nil when it did not finish. Sends no bytes, so `media.data` may be empty.
    func finishedUpload(
        of media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation
    ) async throws -> UUID?
}

extension DailyAnswerMediaUploading {
    // swiftlint:disable async_without_await
    func finishedUpload(
        of _: DailyAnswerUploadMedia,
        answerID _: UUID,
        coupleID _: UUID,
        reserveOperation _: SyncClientOperation
    ) async throws -> UUID? { nil }
    // swiftlint:enable async_without_await
}

/// Uploads daily-answer media scoped to the `daily_answer_media` parent, so the asset
/// links to a specific answer.
///
/// Question chats reuse it for voice messages with the `thread_message_media` parent.
/// Then `answerID` is the id the message will get.
nonisolated struct LiveDailyAnswerMediaUploadService: DailyAnswerMediaUploading {
    private let uploader: MediaUploader
    private let reservedParentKind: String

    init(client: PaeoniaConvexClient, reservedParentKind: String = "daily_answer_media") {
        uploader = MediaUploader(client: client)
        self.reservedParentKind = reservedParentKind
    }

    func uploadMedia(
        _ media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID {
        try await uploader.upload(
            media.data,
            as: upload(media, answerID: answerID, coupleID: coupleID),
            reserveOperation: reserveOperation,
            finalizeOperation: finalizeOperation
        )
    }

    /// Replays the reservation, which the server answers from its record of the first one.
    func finishedUpload(
        of media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation
    ) async throws -> UUID? {
        let reservation = try await uploader.reserve(
            upload(media, answerID: answerID, coupleID: coupleID),
            operation: reserveOperation
        )
        return reservation.isFinalized ? reservation.mediaAssetID : nil
    }

    private func upload(_ media: DailyAnswerUploadMedia, answerID: UUID, coupleID: UUID) -> MediaUpload {
        MediaUpload(
            parentKind: reservedParentKind,
            parentID: answerID,
            purpose: media.purpose.rawValue,
            mediaType: media.purpose.mediaType(for: media.mimeType),
            mimeType: media.mimeType,
            fileExtension: media.fileExtension,
            coupleID: coupleID,
            accessibilityText: media.accessibilityText,
            width: media.width,
            height: media.height,
            durationMs: media.durationMs
        )
    }
}
