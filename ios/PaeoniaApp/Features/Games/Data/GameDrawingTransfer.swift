import Foundation

nonisolated enum GameDrawingTransferError: Error, Equatable, Sendable {
    case downloadUnavailable
}

/// What an uploaded drawing hangs on: the move or part it belongs to, the kind
/// of file it is, and the game whose folder holds it. The backend checks the
/// kind and the purpose together (`create_pending_media_upload` in `media.ts`).
nonisolated struct GameUploadParent: Equatable, Sendable {
    /// `reserved_parent_kind`, such as `game_move`.
    var kind: String
    /// `reserved_parent_id`, such as the round id.
    var id: UUID
    /// `upload_purpose`, such as `game_drawing_payload`.
    var purpose: String
    var gameID: UUID
    /// Only a full drawing carries authored text. A clipped fold strip never does.
    var accessibilityText: String?

    /// The finished drawing of a Draw & Guess round.
    static func drawAndGuessRound(gameID: UUID, roundID: UUID, accessibilityText: String? = nil) -> GameUploadParent {
        GameUploadParent(kind: "game_move", id: roundID, purpose: "game_drawing_payload",
                         gameID: gameID, accessibilityText: accessibilityText)
    }
}

/// Sends a finished drawing to the game bucket and fetches the partner's.
nonisolated protocol GameDrawingTransferring: Sendable {
    /// Reserves, uploads, and finalizes the `.pkdrawing` for `parent`, and returns
    /// the media asset id for the game's submit call. A retry with the same
    /// operations returns the same asset, so a lost response never uploads twice.
    func uploadDrawing(
        _ data: Data,
        parent: GameUploadParent,
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

    func uploadDrawing(
        _ data: Data,
        parent: GameUploadParent,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID {
        try await PaeoniaSignedIn.require(isSignedIn)
        return try await MediaUploader(client: client).upload(
            data,
            as: MediaUpload(
                parentKind: parent.kind,
                parentID: parent.id,
                purpose: parent.purpose,
                mediaType: "drawing_payload",
                mimeType: Self.payloadMimeType,
                fileExtension: Self.payloadFileExtension,
                coupleID: coupleID,
                pathContext: .game(parent.gameID),
                accessibilityText: parent.accessibilityText
            ),
            reserveOperation: reserveOperation,
            finalizeOperation: finalizeOperation
        )
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
