import Foundation

/// What a send names besides the photo: the spot and what the reveal shows with it.
nonisolated struct GuessMySpotSendDetails: Codable, Equatable, Sendable {
    let roundID: UUID
    /// The round this send makes. The server refuses it once that turn moved on.
    let roundNumber: Int
    let spot: GuessMySpotCoordinate
    var placeName: String?
    let takenOn: String?
    /// The city alone and the country code, which the memory map counts.
    var placeCity: String?
    var placeCountryCode: String?

    /// Fills the place from a lookup.
    mutating func name(_ place: GuessMySpotPlace?) {
        placeName = place?.name
        placeCity = place?.city
        placeCountryCode = place?.countryCode
    }
}

/// The Guess my spot backend functions (`backend/convex/guessMySpot.ts`), and the
/// photo upload through the shared media upload. Presence, invites and settings
/// are in `GamesGateway`. Writes that take a client operation are safe to retry:
/// the server runs each operation id once.
nonisolated protocol GuessMySpotGateway: Sendable {
    /// One-shot read of what the live feed follows.
    func loadGuessMySpot() async throws -> RemoteGuessMySpotState
    /// Makes the couple's game with this person sending first, or returns the one there is.
    func ensureGuessMySpotGame() async throws -> RemoteGuessMySpotEnsureResult
    /// Reserves, uploads and finalizes the round's photo. Returns its media asset id.
    func uploadGuessMySpotPhoto( // swiftlint:disable:this function_parameter_count
        _ jpeg: Data,
        width: Int,
        height: Int,
        roundID: UUID,
        coupleID: UUID,
        reserve: SyncClientOperation,
        finalize: SyncClientOperation
    ) async throws -> UUID
    func sendGuessMySpotPhoto(
        _ details: GuessMySpotSendDetails,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound
    /// Answers with the guessed round, which carries the real spot.
    func submitGuessMySpotGuess(
        roundID: UUID,
        guess: GuessMySpotCoordinate,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound
    /// The server keeps the first time, so a retry is safe.
    func markGuessMySpotRevealSeen(roundID: UUID) async throws -> RemoteGuessMySpotRevealSeenResult
    func loadGuessMySpotHistory() async throws -> RemoteGuessMySpotHistory
    /// Deletes a round this person sent, with its photo, for both partners.
    func deleteGuessMySpotRound(roundID: UUID, operation: SyncClientOperation) async throws
        -> RemoteGuessMySpotDeleteResult
}

nonisolated extension LiveGamesGateway: GuessMySpotGateway {
    func loadGuessMySpot() async throws -> RemoteGuessMySpotState {
        try await client.query("guessMySpot:get_guess_my_spot")
    }

    func ensureGuessMySpotGame() async throws -> RemoteGuessMySpotEnsureResult {
        try await client.mutation("guessMySpot:ensure_guess_my_spot_game")
    }

    func uploadGuessMySpotPhoto( // swiftlint:disable:this function_parameter_count
        _ jpeg: Data,
        width: Int,
        height: Int,
        roundID: UUID,
        coupleID: UUID,
        reserve: SyncClientOperation,
        finalize: SyncClientOperation
    ) async throws -> UUID {
        let media = MemoryUploadMedia(
            data: jpeg,
            purpose: .guessMySpot,
            mimeType: "image/jpeg",
            fileExtension: "jpg",
            width: width,
            height: height
        )
        let result = try await LiveMemoryMediaUploadService(client: client).uploadMedia(
            media,
            memoryMediaID: roundID,
            coupleID: coupleID,
            reserveOperation: reserve,
            finalizeOperation: finalize
        )
        return result.mediaAssetID
    }

    func sendGuessMySpotPhoto(
        _ details: GuessMySpotSendDetails,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
        try await client.mutation(
            "guessMySpot:send_guess_my_spot_photo",
            args: GuessMySpotSendRequest(details: details, mediaAssetID: mediaAssetID, operation: operation)
        )
    }

    func submitGuessMySpotGuess(
        roundID: UUID,
        guess: GuessMySpotCoordinate,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
        try await client.mutation(
            "guessMySpot:submit_guess_my_spot_guess",
            args: GuessMySpotGuessRequest(
                roundID: roundID,
                guess: guess,
                operation: GameClientOperationFields(operation)
            )
        )
    }

    func markGuessMySpotRevealSeen(roundID: UUID) async throws -> RemoteGuessMySpotRevealSeenResult {
        try await client.mutation(
            "guessMySpot:mark_guess_my_spot_reveal_seen",
            args: ["p_round_id": roundID.uuidString.lowercased()]
        )
    }

    func loadGuessMySpotHistory() async throws -> RemoteGuessMySpotHistory {
        try await client.query("guessMySpot:get_guess_my_spot_history")
    }

    func deleteGuessMySpotRound(roundID: UUID, operation: SyncClientOperation) async throws
        -> RemoteGuessMySpotDeleteResult {
        try await client.mutation(
            "guessMySpot:delete_guess_my_spot_round",
            args: GuessMySpotRoundRequest(roundID: roundID, operation: GameClientOperationFields(operation))
        )
    }
}

// The protocol is async, and this stand-in fails at once.
// swiftlint:disable async_without_await
nonisolated extension UnavailableGamesGateway: GuessMySpotGateway {
    func loadGuessMySpot() async throws -> RemoteGuessMySpotState {
        throw Unavailable()
    }

    func ensureGuessMySpotGame() async throws -> RemoteGuessMySpotEnsureResult {
        throw Unavailable()
    }

    func uploadGuessMySpotPhoto( // swiftlint:disable:this function_parameter_count
        _: Data,
        width _: Int,
        height _: Int,
        roundID _: UUID,
        coupleID _: UUID,
        reserve _: SyncClientOperation,
        finalize _: SyncClientOperation
    ) async throws -> UUID {
        throw Unavailable()
    }

    func sendGuessMySpotPhoto(
        _: GuessMySpotSendDetails,
        mediaAssetID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
        throw Unavailable()
    }

    func submitGuessMySpotGuess(
        roundID _: UUID,
        guess _: GuessMySpotCoordinate,
        operation _: SyncClientOperation
    ) async throws -> RemoteGuessMySpotRound {
        throw Unavailable()
    }

    func markGuessMySpotRevealSeen(roundID _: UUID) async throws -> RemoteGuessMySpotRevealSeenResult {
        throw Unavailable()
    }

    func loadGuessMySpotHistory() async throws -> RemoteGuessMySpotHistory {
        throw Unavailable()
    }

    func deleteGuessMySpotRound(roundID _: UUID, operation _: SyncClientOperation) async throws
        -> RemoteGuessMySpotDeleteResult {
        throw Unavailable()
    }
}
// swiftlint:enable async_without_await

// MARK: - Request bodies

nonisolated private struct GuessMySpotSendRequest: Encodable {
    let details: GuessMySpotSendDetails
    let mediaAssetID: UUID
    let operation: SyncClientOperation

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case roundNumber = "p_round_number"
        case mediaAssetID = "p_media_asset_id"
        case latitude = "p_latitude"
        case longitude = "p_longitude"
        case placeName = "p_place_name"
        case placeCity = "p_place_city"
        case placeCountryCode = "p_place_country_code"
        case takenOn = "p_taken_on"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(details.roundID, forKey: .roundID)
        try container.encode(Double(details.roundNumber), forKey: .roundNumber)
        try container.encode(mediaAssetID, forKey: .mediaAssetID)
        try container.encode(details.spot.latitude, forKey: .latitude)
        try container.encode(details.spot.longitude, forKey: .longitude)
        try container.encodeIfPresent(details.placeName, forKey: .placeName)
        try container.encodeIfPresent(details.placeCity, forKey: .placeCity)
        try container.encodeIfPresent(details.placeCountryCode, forKey: .placeCountryCode)
        try container.encodeIfPresent(details.takenOn, forKey: .takenOn)
        try GameClientOperationFields(operation).encode(to: encoder)
    }
}

nonisolated private struct GuessMySpotRoundRequest: Encodable {
    let roundID: UUID
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct GuessMySpotGuessRequest: Encodable {
    let roundID: UUID
    let guess: GuessMySpotCoordinate
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case latitude = "p_latitude"
        case longitude = "p_longitude"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roundID, forKey: .roundID)
        try container.encode(guess.latitude, forKey: .latitude)
        try container.encode(guess.longitude, forKey: .longitude)
        try operation.encode(to: encoder)
    }
}
