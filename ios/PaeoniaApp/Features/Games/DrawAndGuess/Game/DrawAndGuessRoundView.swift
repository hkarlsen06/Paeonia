import Foundation

/// One guess as the screens show it.
nonisolated struct DrawAndGuessAttemptView: Identifiable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    /// Lowercase on the server. Screens show capitals.
    let text: String
    let isCorrect: Bool
    let createdAt: Date
    /// Saved on this phone and not sent yet.
    let isPending: Bool
}

/// The current round with this phone's unsent moves applied. A guess or a give
/// up that is still queued already ends the round here, so the person never
/// waits for the network to see the result of what they did.
nonisolated struct DrawAndGuessRoundView: Identifiable, Equatable, Sendable {
    let id: UUID
    let number: Int
    let drawerUserID: UUID
    let guesserUserID: UUID
    var state: DrawAndGuessRoundState
    let difficulty: DrawAndGuessDifficulty
    /// Lowercase.
    let word: String
    let points: Int
    let drawingMediaAssetID: UUID?
    /// The server has the drawing, or it is queued on this phone.
    var isDrawingSent: Bool
    let startedAt: Date
    let guesserFirstSeenAt: Date?
    /// When a queued correct guess was made, before the server confirms it.
    var localSolvedAt: Date?
    let endedAt: Date?
    let solveMs: Int?
    /// A queued correct guess carries the tier the screen showed, until the server confirms.
    var speedBonus: Int
    /// A queued correct guess carries the phone's prediction, until the server confirms.
    var firstTryBonus: Int
    var hintsUsed: Int
    let personalBest: Bool
    let drawerResultSeenAt: Date?
    let guesserResultSeenAt: Date?
    var attempts: [DrawAndGuessAttemptView]
    /// The word pick is queued and the server does not know the round yet.
    let isOnlyOnThisPhone: Bool

    init(_ round: RemoteDrawAndGuessRound) {
        id = round.id
        number = round.roundNumber
        drawerUserID = round.drawerUserID
        guesserUserID = round.guesserUserID
        state = round.state
        difficulty = round.difficulty
        word = round.word
        points = round.points
        drawingMediaAssetID = round.drawingMediaAssetID
        isDrawingSent = round.drawingMediaAssetID != nil
        startedAt = round.startedAt
        guesserFirstSeenAt = round.guesserFirstSeenAt
        localSolvedAt = nil
        endedAt = round.endedAt
        solveMs = round.solveMs
        speedBonus = round.speedBonus
        firstTryBonus = round.firstTryBonus
        hintsUsed = round.hintsUsed
        personalBest = round.personalBest
        drawerResultSeenAt = round.drawerResultSeenAt
        guesserResultSeenAt = round.guesserResultSeenAt
        attempts = round.attempts.map {
            DrawAndGuessAttemptView(
                id: $0.id,
                userID: $0.userID,
                text: $0.text,
                isCorrect: $0.correct,
                createdAt: $0.createdAt,
                isPending: false
            )
        }
        isOnlyOnThisPhone = false
    }

    /// A round the drawer started offline.
    init(pick: GamePickWordPayload, number: Int, drawerUserID: UUID, guesserUserID: UUID) {
        id = pick.roundID
        self.number = number
        self.drawerUserID = drawerUserID
        self.guesserUserID = guesserUserID
        state = .drawing
        difficulty = pick.choice
        word = pick.word.lowercased()
        points = pick.points
        drawingMediaAssetID = nil
        isDrawingSent = false
        startedAt = pick.createdAt
        guesserFirstSeenAt = nil
        localSolvedAt = nil
        endedAt = nil
        solveMs = nil
        speedBonus = 0
        firstTryBonus = 0
        hintsUsed = 0
        personalBest = false
        drawerResultSeenAt = nil
        guesserResultSeenAt = nil
        attempts = []
        isOnlyOnThisPhone = true
    }

    func isDrawer(_ userID: UUID) -> Bool {
        drawerUserID == userID
    }

    var isFinished: Bool {
        state.isFinished
    }

    /// The server has this person's "I have seen the result" for the round.
    func hasSeenResult(_ userID: UUID) -> Bool {
        (drawerUserID == userID ? drawerResultSeenAt : guesserResultSeenAt) != nil
    }
}
