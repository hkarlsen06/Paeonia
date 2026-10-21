import Foundation

/// One of the three words offered to the drawer.
nonisolated struct DrawAndGuessWordChoice: Identifiable, Equatable, Sendable {
    let difficulty: DrawAndGuessDifficulty
    let wordID: String
    /// Lowercase.
    let word: String
    let points: Int

    var id: DrawAndGuessDifficulty { difficulty }

    init(_ choice: RemoteDrawAndGuessChoice) {
        difficulty = choice.difficulty
        wordID = choice.wordID
        word = choice.word
        points = choice.points
    }

    init(difficulty: DrawAndGuessDifficulty, wordID: String, word: String, points: Int) {
        self.difficulty = difficulty
        self.wordID = wordID
        self.word = word
        self.points = points
    }
}

/// How the typed "Draw your own" word reads.
nonisolated enum DrawAndGuessCustomWordValidation: Equatable, Sendable {
    case empty
    /// A word that can be sent, trimmed and with single spaces.
    case valid(String)
    case invalid(DrawAndGuessCustomWord.Failure)

    init(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self = .empty
            return
        }
        switch DrawAndGuessCustomWord.validate(text) {
        case let .success(word):
            self = .valid(word)
        case let .failure(failure):
            self = .invalid(failure)
        }
    }

    var word: String? {
        if case let .valid(word) = self { word } else { nil }
    }
}

/// Where the partner is, as far as the relay room and the open-screen heartbeat tell.
nonisolated enum DrawAndGuessPartnerPresence: Equatable, Sendable {
    case away
    /// Has the game screen open, and the room does not say more.
    case here
    /// In the live room, watching the drawing.
    case watching
    /// In the live room, drawing.
    case drawing
    /// On the screen where a word is picked.
    case choosing
    /// Looking at the result of a round.
    case result

    var isHere: Bool {
        self != .away
    }

    /// The partner's phone told the room what it is doing.
    var isInRoom: Bool {
        self != .away && self != .here
    }

    /// The left side of the drawer's live row.
    func drawingLine(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .watching: .gamesDrawAndGuessDrawWatching(partnerName)
        case .result: .gamesDrawAndGuessDrawLookingAtResult(partnerName)
        case .choosing: .gamesDrawAndGuessWaitChoosing(partnerName)
        case .here, .drawing: .gamesDrawAndGuessDrawHere(partnerName)
        case .away: .gamesDrawAndGuessDrawLater(partnerName)
        }
    }
}

/// What the drawer's result screen says about the drawing they sent.
nonisolated enum DrawAndGuessSentStatus: Equatable, Sendable {
    /// The partner is on the guess screen right now.
    case looking
    /// The partner saw the drawing and has left the guess screen.
    case seen
    case notSeen

    /// Whether the partner has the drawing is separate from whether it has left
    /// this phone. A first look on the server or live watching shows they have it.
    ///
    /// - Parameters:
    ///   - guesserFirstSeenAt: The server's record of the partner's first look.
    ///   - isPartnerWatchingLive: The partner has this phone's whole canvas through the live room.
    ///   - isWaitingToSend: The drawing is still on this phone, so without a first look
    ///     or live watching the partner can't have it.
    static func make(
        partner: DrawAndGuessPartnerPresence,
        guesserFirstSeenAt: Date?,
        isPartnerWatchingLive: Bool = false,
        isWaitingToSend: Bool = false
    ) -> DrawAndGuessSentStatus {
        let partnerHasIt = guesserFirstSeenAt != nil || isPartnerWatchingLive || !isWaitingToSend
        if partner == .watching, partnerHasIt {
            return .looking
        }
        return guesserFirstSeenAt == nil ? .notSeen : .seen
    }

    func line(partnerName: String) -> LocalizedStringResource {
        switch self {
        case .looking: .gamesDrawAndGuessResultLooking(partnerName)
        case .seen: .gamesDrawAndGuessResultSeen(partnerName)
        case .notSeen: .gamesDrawAndGuessResultNotSeen(partnerName)
        }
    }
}

/// What the guesser looks at while guessing.
nonisolated enum DrawAndGuessGuessSource: Equatable, Sendable {
    /// The drawing played back from the saved file.
    case replay
    /// The live room's canvas, because the guesser watched the drawing happen.
    case live
}

/// The result of a finished round.
nonisolated struct DrawAndGuessReveal: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case iSolvedIt
        case partnerSolvedIt
        /// This person pressed "Show me".
        case iGaveUp
        case partnerGaveUp
    }

    let outcome: Outcome
    /// Lowercase.
    let word: String
    let difficulty: DrawAndGuessDifficulty
    /// What the word is worth.
    let wordPoints: Int
    /// The speed bonus, 0 to 2. On a result still on this phone it is the tier
    /// the screen showed, and the server's number replaces it.
    let speedBonus: Int
    /// 1 for a correct first attempt without hints. On a result still on this
    /// phone it is the phone's prediction.
    let firstTryBonus: Int
    /// How many letters the hints showed.
    let hintsUsed: Int
    /// The guesser's fastest hint-free solve yet. Only the server says so.
    let personalBest: Bool
    /// How long the guess took, counted from the first look at the drawing.
    let solveDuration: TimeInterval?
    /// What this person earned. The drawer gets the word's points. The guesser also
    /// gets the speed bonus and the first-try bonus.
    let pointsForMe: Int
    /// What the couple's shared score grew by.
    let pointsForCouple: Int
    let attempts: [DrawAndGuessAttemptView]
    /// The server has confirmed the result, so the points and the time are final.
    let isConfirmed: Bool

    var isSolved: Bool {
        outcome == .iSolvedIt || outcome == .partnerSolvedIt
    }

    /// Past this, the time says more about the day than about the guess.
    static let longestShownSolveTime: TimeInterval = 600

    /// The solve time worth showing, or nil when it is missing or too long.
    var shownSolveDuration: TimeInterval? {
        guard let solveDuration, solveDuration <= Self.longestShownSolveTime else { return nil }
        return solveDuration
    }

    /// How many guesses it took, the right one included.
    var tries: Int {
        attempts.filter { !$0.isCorrect }.count + 1
    }

    /// One sentence for the drawer: "Robin got it in 18 seconds, on the first try."
    /// The time is left out when it is missing or too long to mean anything.
    /// With hints it says how many instead of how many tries.
    func solvedLine(partnerName: String) -> LocalizedStringResource {
        if hintsUsed > 0 {
            let hints = String(localized: .gamesDrawAndGuessHints(hintsUsed))
            if let duration = shownSolveDuration {
                return .gamesDrawAndGuessResultSolvedTimedHints(partnerName, Self.spokenDuration(duration), hints)
            }
            return .gamesDrawAndGuessResultSolvedHints(partnerName, hints)
        }
        return switch (shownSolveDuration, tries) {
        case (let duration?, 1):
            .gamesDrawAndGuessResultSolvedTimedFirstTry(partnerName, Self.spokenDuration(duration))
        case (let duration?, let tries):
            .gamesDrawAndGuessResultSolvedTimedTries(partnerName, Self.spokenDuration(duration), tries)
        case (nil, 1):
            .gamesDrawAndGuessResultSolvedFirstTry(partnerName)
        case (nil, let tries):
            .gamesDrawAndGuessResultSolvedTries(partnerName, tries)
        }
    }

    /// "24 seconds" or "1 minute, 5 seconds".
    static func spokenDuration(_ duration: TimeInterval) -> String {
        Duration.seconds(Int(duration.rounded())).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}
