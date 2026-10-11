import Foundation

/// How far one drawing's upload got. It is saved with the "not sent yet"
/// marker, so a retry reuses the same revision, reservation, storage object,
/// and operation IDs. The server replays an operation it already applied
/// (`runClientOperation`), so a response lost after the server committed is
/// answered from the stored result instead of creating a second revision.
nonisolated struct WidgetUploadProgress: Codable, Equatable, Sendable {
    /// The parts of `MediaUploadReservation` needed to finalize again.
    struct Reservation: Codable, Equatable, Sendable {
        let mediaAssetID: UUID
        let bucket: String
        let storagePath: String
        let uploadURL: URL

        init(_ reservation: MediaUploadReservation) {
            mediaAssetID = reservation.mediaAssetID
            bucket = reservation.bucket
            storagePath = reservation.storagePath
            uploadURL = reservation.uploadURL
        }

        var mediaUploadReservation: MediaUploadReservation {
            MediaUploadReservation(
                mediaAssetID: mediaAssetID,
                bucket: bucket,
                storagePath: storagePath,
                uploadURL: uploadURL
            )
        }
    }

    let revisionID: UUID
    let reserveOperation: SyncClientOperation
    let finalizeOperation: SyncClientOperation
    var reservation: Reservation?
    var storageID: String?
    var isFinalized = false
    /// The exact submit request, including its parent and validation time, so a
    /// replay matches the stored request.
    var submission: WidgetDrawingRevisionSubmission?
    var submitOperation: SyncClientOperation?

    init(revisionID: UUID, reserveOperation: SyncClientOperation, finalizeOperation: SyncClientOperation) {
        self.revisionID = revisionID
        self.reserveOperation = reserveOperation
        self.finalizeOperation = finalizeOperation
    }
}
