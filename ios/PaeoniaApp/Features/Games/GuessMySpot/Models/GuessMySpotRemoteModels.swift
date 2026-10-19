import CoreLocation
import Foundation

/// A point on the map, in degrees.
nonisolated struct GuessMySpotCoordinate: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// One round: the sender's photo and spot and, once guessed, the partner's guess.
nonisolated struct RemoteGuessMySpotRound: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundNumber: Int
    let senderUserID: UUID
    let guesserUserID: UUID
    let photoMediaAssetID: UUID
    let photoWidth: Int?
    let photoHeight: Int?
    /// The real spot. The guesser gets it, the place name and the date only once the round has a guess.
    var spotLatitude: Double?
    var spotLongitude: Double?
    var placeName: String?
    /// The city alone and the ISO country code, for the memory map's totals.
    var placeCity: String?
    var placeCountryCode: String?
    /// The day the photo was taken, `YYYY-MM-DD`.
    var takenOn: String?
    let sentAt: Date
    var guessLatitude: Double?
    var guessLongitude: Double?
    var distanceM: Int?
    var points: Int?
    var guessedAt: Date?
    var myRevealSeenAt: Date?
    /// The sender may delete it: both have seen its reveal.
    var canDelete: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case roundNumber = "round_number"
        case senderUserID = "sender_user_id"
        case guesserUserID = "guesser_user_id"
        case photoMediaAssetID = "photo_media_asset_id"
        case photoWidth = "photo_width"
        case photoHeight = "photo_height"
        case spotLatitude = "spot_latitude"
        case spotLongitude = "spot_longitude"
        case placeName = "place_name"
        case placeCity = "place_city"
        case placeCountryCode = "place_country_code"
        case takenOn = "taken_on"
        case sentAt = "sent_at"
        case guessLatitude = "guess_latitude"
        case guessLongitude = "guess_longitude"
        case distanceM = "distance_m"
        case points
        case guessedAt = "guessed_at"
        case myRevealSeenAt = "my_reveal_seen_at"
        case canDelete = "can_delete"
    }
}

nonisolated extension RemoteGuessMySpotRound {
    var spot: GuessMySpotCoordinate? {
        guard let spotLatitude, let spotLongitude else { return nil }
        return GuessMySpotCoordinate(latitude: spotLatitude, longitude: spotLongitude)
    }

    var guess: GuessMySpotCoordinate? {
        get {
            guard let guessLatitude, let guessLongitude else { return nil }
            return GuessMySpotCoordinate(latitude: guessLatitude, longitude: guessLongitude)
        }
        set {
            guessLatitude = newValue?.latitude
            guessLongitude = newValue?.longitude
        }
    }

    var isGuessed: Bool {
        guess != nil
    }

    /// The distance once both the guess and the spot are known.
    var knownDistance: Int? {
        distanceM ?? spot.flatMap { spot in guess.map { GuessMySpotRules.distanceMeters($0, spot) } }
    }

    var knownPoints: Int? {
        points ?? knownDistance.map(GuessMySpotRules.points(distanceMeters:))
    }
}

nonisolated struct RemoteGuessMySpotGame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Who acts next: the guesser while the newest round has no guess, the next sender after that.
    var turnUserID: UUID
    let turnStartedAt: Date
    var sharedPoints: Int
    /// Each partner's own total, for "against each other". Only the guesser scores.
    var myPoints: Int
    var partnerPoints: Int
    var roundCount: Int
    let version: Int
    let createdByUserID: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case turnUserID = "turn_user_id"
        case turnStartedAt = "turn_started_at"
        case sharedPoints = "shared_points"
        case myPoints = "my_points"
        case partnerPoints = "partner_points"
        case roundCount = "round_count"
        case version
        case createdByUserID = "created_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `guessMySpot:get_guess_my_spot`: everything the game's screens show.
nonisolated struct RemoteGuessMySpotState: Codable, Equatable, Sendable {
    let userID: UUID
    let partnerUserID: UUID?
    let coupleID: UUID
    /// The server's data epoch (`PAEONIA_DATA_EPOCH`). It changes only after a backup
    /// restore or a hand edit of the games, and then the server's copy wins.
    let dataEpoch: String
    /// Nil before the couple's first game.
    let game: RemoteGuessMySpotGame?
    let currentRound: RemoteGuessMySpotRound?
    /// The round before the newest, so a reveal this person missed still shows.
    let previousRound: RemoteGuessMySpotRound?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case partnerUserID = "partner_user_id"
        case coupleID = "couple_id"
        case dataEpoch = "data_epoch"
        case game
        case currentRound = "current_round"
        case previousRound = "previous_round"
    }
}

nonisolated extension RemoteGuessMySpotState {
    /// This state is behind `other`: the same game at a lower version, or no game
    /// while the other has one. A late answer like that must not replace a newer one.
    func isOlder(than other: RemoteGuessMySpotState) -> Bool {
        // Another person, couple or data epoch is never older, so it can't win over a purge or a restore.
        guard userID == other.userID, coupleID == other.coupleID, dataEpoch == other.dataEpoch else { return false }
        guard let game else { return other.game != nil }
        guard let otherGame = other.game, game.id == otherGame.id else { return false }
        return game.version < otherGame.version
    }
}

// MARK: - History

nonisolated struct RemoteGuessMySpotGuesserRecord: Codable, Equatable, Sendable {
    let guesses: Int
    /// Nil before the first guess.
    let closestM: Int?
    let averageM: Int?

    enum CodingKeys: String, CodingKey {
        case guesses
        case closestM = "closest_m"
        case averageM = "average_m"
    }
}

nonisolated struct RemoteGuessMySpotRecords: Codable, Equatable, Sendable {
    let sharedPoints: Int
    let myPoints: Int
    let partnerPoints: Int
    /// This person as the guesser.
    let mine: RemoteGuessMySpotGuesserRecord
    let partner: RemoteGuessMySpotGuesserRecord

    enum CodingKeys: String, CodingKey {
        case sharedPoints = "shared_points"
        case myPoints = "my_points"
        case partnerPoints = "partner_points"
        case mine
        case partner
    }
}

/// `guessMySpot:get_guess_my_spot_history`: the newest guessed rounds, newest first.
nonisolated struct RemoteGuessMySpotHistory: Codable, Equatable, Sendable {
    let rounds: [RemoteGuessMySpotRound]
    let records: RemoteGuessMySpotRecords
}

// MARK: - Mutation results

nonisolated struct RemoteGuessMySpotEnsureResult: Decodable, Equatable, Sendable {
    let gameID: UUID
    let created: Bool

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case created
    }
}

nonisolated struct RemoteGuessMySpotDeleteResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case deletedAt = "deleted_at"
    }
}

nonisolated struct RemoteGuessMySpotRevealSeenResult: Decodable, Equatable, Sendable {
    let roundID: UUID
    let revealSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case revealSeenAt = "reveal_seen_at"
    }
}
