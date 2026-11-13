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
    /// What the word is worth.
    let wordPoints: Int
    /// The speed bonus, 0 to 2. On a result still on this phone it is the tier
    /// the screen showed, and the server's number replaces it.
    let speedBonus: Int
    /// 1 for a correct first attempt without hints. On a result still on this
    /// phone it is the phone's prediction.
    let firstTryBonus: Int
    /// What this person earned. The drawer gets the word's points. The guesser also
    /// gets the speed bonus and the first-try bonus.
    let pointsForMe: Int
    let attempts: [DrawAndGuessAttemptView]
    /// The server has confirmed the result, so the points are final.
    let isConfirmed: Bool

    var isSolved: Bool {
        outcome == .iSolvedIt || outcome == .partnerSolvedIt
    }
}
