import CryptoKit
import Foundation

nonisolated enum GameDrawingTransferError: Error, Equatable, Sendable {
    case reservationFailed
    case finalizeFailed
    case downloadUnavailable
}

/// Sends a finished drawing to the game bucket and fetches the partner's.
nonisolated protocol GameDrawingTransferring: Sendable {
    /// Reserves, uploads, and finalizes the `.pkdrawing` for a round, and returns
    /// the media asset id for `drawAndGuess:submit_drawing`. A retry with the same
    /// operations returns the same asset, so a lost response never uploads twice.
    func uploadDrawing( // swiftlint:disable:this function_parameter_count
        _ data: Data,
        gameID: UUID,
        roundID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data
}

nonisolated struct LiveGameDrawingTransfer: GameDrawingTransferring {
    static let payloadMimeType = "application/octet-stream"
    static let payloadFileExtension = "pkdrawing"
    private static let signedURLExpiresInSeconds = 900

    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func uploadDrawing( // swiftlint:disable:this function_parameter_count
        _ data: Data,
        gameID: UUID,
        roundID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID {
        try await PaeoniaSignedIn.require(isSignedIn)

        let reservations: [MediaUploadReservation] = try await client.mutation(
            "media:create_pending_media_upload",
            args: ReserveGameDrawingRequest(
                operation: reserveOperation,
                gameID: gameID,
                roundID: roundID,
                coupleID: coupleID
            )
        )
        guard let reservation = reservations.first else {
            throw GameDrawingTransferError.reservationFailed
        }
        let storageID = try await client.upload(data, contentType: Self.payloadMimeType, to: reservation.uploadURL)
        let finalized: [FinalizedMediaUploadResponse] = try await client.mutation(
            "media:finalize_media_upload",
            args: FinalizeGameDrawingRequest(
                reservation: reservation,
                storageID: storageID,
                reservedByOperationID: reserveOperation.id,
                operation: finalizeOperation,
                roundID: roundID,
                data: data
            )
        )
        guard let first = finalized.first, first.uploadStatus == "finalized" else {
            throw GameDrawingTransferError.finalizeFailed
        }
        return first.mediaAssetID
    }

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data {
        guard let url = try await client.signedMediaURL(
            for: mediaAssetID,
            expiresInSeconds: Self.signedURLExpiresInSeconds
        ) else {
            throw GameDrawingTransferError.downloadUnavailable
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GameDrawingTransferError.downloadUnavailable
        }
        return data
    }
}

nonisolated private struct ReserveGameDrawingRequest: Encodable {
    let operation: GameClientOperationFields
    let reservedParentKind = "game_move"
    let reservedParentID: UUID
    let uploadPurpose = "game_drawing_payload"
    let mediaType = "drawing_payload"
    let fileExtension = LiveGameDrawingTransfer.payloadFileExtension
    let coupleID: UUID
    let pathContext: PathContext

    struct PathContext: Encodable {
        let gameID: UUID

        enum CodingKeys: String, CodingKey {
            case gameID = "game_id"
        }
    }

    init(operation: SyncClientOperation, gameID: UUID, roundID: UUID, coupleID: UUID) {
        self.operation = GameClientOperationFields(operation)
        reservedParentID = roundID
        self.coupleID = coupleID
        pathContext = PathContext(gameID: gameID)
    }

    enum CodingKeys: String, CodingKey {
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case fileExtension = "p_file_extension"
        case coupleID = "p_couple_id"
        case pathContext = "p_path_context"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reservedParentKind, forKey: .reservedParentKind)
        try container.encode(reservedParentID, forKey: .reservedParentID)
        try container.encode(uploadPurpose, forKey: .uploadPurpose)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(fileExtension, forKey: .fileExtension)
        try container.encode(coupleID, forKey: .coupleID)
        try container.encode(pathContext, forKey: .pathContext)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct FinalizeGameDrawingRequest: Encodable {
    let operation: GameClientOperationFields
    let mediaAssetID: UUID
    let reservedByOperationID: UUID
    let bucket: String
    let storagePath: String
    let storageID: String
    let reservedParentKind = "game_move"
    let reservedParentID: UUID
    let uploadPurpose = "game_drawing_payload"
    let mediaType = "drawing_payload"
    let mimeType = LiveGameDrawingTransfer.payloadMimeType
    let byteSize: Int64
    let sha256Hex: String

    init(
        reservation: MediaUploadReservation,
        storageID: String,
        reservedByOperationID: UUID,
        operation: SyncClientOperation,
        roundID: UUID,
        data: Data
    ) {
        self.operation = GameClientOperationFields(operation)
        mediaAssetID = reservation.mediaAssetID
        self.reservedByOperationID = reservedByOperationID
        bucket = reservation.bucket
        storagePath = reservation.storagePath
        self.storageID = storageID
        reservedParentID = roundID
        byteSize = Int64(data.count)
        sha256Hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case reservedByOperationID = "p_reserved_by_client_operation_id"
        case bucket = "p_bucket"
        case storagePath = "p_storage_path"
        case storageID = "p_storage_id"
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case mimeType = "p_mime_type"
        case byteSize = "p_byte_size"
        case sha256Hex = "p_sha256_hex"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mediaAssetID, forKey: .mediaAssetID)
        try container.encode(reservedByOperationID, forKey: .reservedByOperationID)
        try container.encode(bucket, forKey: .bucket)
        try container.encode(storagePath, forKey: .storagePath)
        try container.encode(storageID, forKey: .storageID)
        try container.encode(reservedParentKind, forKey: .reservedParentKind)
        try container.encode(reservedParentID, forKey: .reservedParentID)
        try container.encode(uploadPurpose, forKey: .uploadPurpose)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(sha256Hex, forKey: .sha256Hex)
        try operation.encode(to: encoder)
    }
}
