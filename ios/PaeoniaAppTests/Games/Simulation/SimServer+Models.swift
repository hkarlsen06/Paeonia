import Foundation
@testable import PaeoniaApp

extension SimServer {
    struct Round {
        let id: UUID
        let number: Int
        let drawer: UUID
        let guesser: UUID
        var state: DrawAndGuessRoundState
        let difficulty: DrawAndGuessDifficulty
        let wordID: String?
        let word: String
        let points: Int
        var drawingAssetID: UUID?
        var submittedAt: Date?
        let startedAt: Date
        var firstSeenAt: Date?
        var endedAt: Date?
        var solveMs: Int?
        var speedBonus = 0
        var firstTryBonus = 0
        var hintsUsed = 0
        var personalBest = false
        var drawerSeenAt: Date?
        var guesserSeenAt: Date?
        var attempts: [RemoteDrawAndGuessAttempt] = []
    }

    struct Asset {
        let id: UUID
        let owner: UUID
        /// The round the drawing was reserved for.
        let roundID: UUID
        let data: Data
        let createdAt: Date
        var queuedForDelete = false
    }

    struct Game {
        let id: UUID
        var state: DrawAndGuessGameState
        var turnUser: UUID
        var turnNumber: Int
        var currentRoundID: UUID?
        var choices: [RemoteDrawAndGuessChoice]?
        var shared = 0
        var points: [UUID: Int] = [:]
        var turnStartedAt: Date
        var version = 1
        let createdAt: Date
        var updatedAt: Date
    }

    struct Settings {
        var playStyle: GamePlayStyle
        var language: GameLanguage
        var updatedBy: UUID
        let createdAt: Date
        var updatedAt: Date
    }
}
