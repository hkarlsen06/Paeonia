import Foundation
@testable import PaeoniaApp

// The protocol is async, and the scripted calls answer at once.
// swiftlint:disable async_without_await

/// Records every board game call and fails the ones a test lists. A class with a
/// lock, so tests read its record without `await`.
final class ScriptedBoardGamesGateway: BoardGamesGateway, @unchecked Sendable {
    struct Failure: Error {}

    private struct Record {
        var calls: [String] = []
        var moves: [BoardGameMovePayload] = []
        var rematches: [BoardGameRematchPayload] = []
        var marks: [Data?] = []
        var failing: Set<String> = []
        var moveError: PaeoniaConvexError?
        var rematchError: PaeoniaConvexError?
        var stateToLoad: RemoteBoardGames?
        var marksToLoad: RemoteBoardGameMarks?
        var historyPages: [Int?: RemoteBoardGameHistoryPage] = [:]
        var historyRequests: [Int?] = []
    }

    private let lock = NSLock()
    private var record = Record()

    private func read<T>(_ value: (Record) -> T) -> T {
        lock.withLock { value(record) }
    }

    private func write(_ change: (inout Record) -> Void) {
        lock.withLock { change(&record) }
    }

    var calls: [String] { read(\.calls) }
    var moves: [BoardGameMovePayload] { read(\.moves) }
    var rematches: [BoardGameRematchPayload] { read(\.rematches) }
    var marks: [Data?] { read(\.marks) }
    /// The cursor of each history read, in order. Nil for the first page.
    var historyRequests: [Int?] { read(\.historyRequests) }

    /// Makes the call of this name throw `Failure` before it does anything.
    func fail(_ name: String) {
        write { $0.failing.insert(name) }
    }

    func unfail(_ name: String) {
        write { $0.failing.remove(name) }
    }

    func setMoveError(_ error: PaeoniaConvexError?) {
        write { $0.moveError = error }
    }

    func setRematchError(_ error: PaeoniaConvexError?) {
        write { $0.rematchError = error }
    }

    /// What the server holds now. `loadBoardGames` returns it, and a move,
    /// a rematch or `ensureGame` answers with its game of that kind.
    func setStateToLoad(_ state: RemoteBoardGames?) {
        write { $0.stateToLoad = state }
    }

    func setMarksToLoad(_ marks: RemoteBoardGameMarks?) {
        write { $0.marksToLoad = marks }
    }

    /// The history page a read with this cursor returns. Nil is the first page.
    func setHistoryPage(_ page: RemoteBoardGameHistoryPage, before cursor: Int?) {
        write { $0.historyPages[cursor] = page }
    }

    private func begin(_ name: String) throws {
        let shouldFail = lock.withLock {
            record.calls.append(name)
            return record.failing.contains(name)
        }
        if shouldFail {
            throw Failure()
        }
    }

    private func answer(for kind: GameKind) throws -> RemoteBoardGame {
        guard let game = read({ $0.stateToLoad })?.game(kind) else { throw Failure() }
        return game
    }

    func loadBoardGames() async throws -> RemoteBoardGames {
        try begin("loadBoardGames")
        guard let state = read({ $0.stateToLoad }) else { throw Failure() }
        return state
    }

    func loadMarks() async throws -> RemoteBoardGameMarks {
        try begin("loadMarks")
        guard let marks = read({ $0.marksToLoad }) else { throw Failure() }
        return marks
    }

    func loadHistory(_: GameKind, beforeGameNumber: Int?, limit _: Int) async throws -> RemoteBoardGameHistoryPage {
        try begin("loadHistory")
        write { $0.historyRequests.append(beforeGameNumber) }
        guard let page = read({ $0.historyPages[beforeGameNumber] }) else { throw Failure() }
        return page
    }

    func ensureGame(_ kind: GameKind) async throws -> RemoteBoardGame {
        try begin("ensureGame")
        return try answer(for: kind)
    }

    func makeMove(_ payload: BoardGameMovePayload, operation _: SyncClientOperation) async throws -> RemoteBoardGame {
        try begin("makeMove")
        write { $0.moves.append(payload) }
        if let error = read({ $0.moveError }) {
            throw error
        }
        return try answer(for: payload.kind)
    }

    func startRematch(
        _ payload: BoardGameRematchPayload,
        operation _: SyncClientOperation
    ) async throws -> RemoteBoardGame {
        try begin("startRematch")
        write { $0.rematches.append(payload) }
        if let error = read({ $0.rematchError }) {
            throw error
        }
        return try answer(for: payload.kind)
    }

    func setMark(_ data: Data?) async throws -> Date? {
        try begin("setMark")
        write { $0.marks.append(data) }
        return data == nil ? nil : BoardGameDataFixture.now
    }
}

// swiftlint:enable async_without_await

/// Deterministic board game data. The person is `me`, and the couple's other
/// partner is `partner`.
enum BoardGameDataFixture {
    static let me = DeveloperGamesFixture.me
    static let partner = DeveloperGamesFixture.partner
    static let now = DeveloperGamesFixture.now
    static let coupleID = DeveloperScenarioFixture.coupleID
    static let gameID = UUID(uuidString: "dddddddd-0000-4000-8000-000000000001") ?? UUID()
    static let otherGameID = UUID(uuidString: "dddddddd-0000-4000-8000-000000000002") ?? UUID()

    /// Connect Four moves that end the game with player one's four in column 0.
    static let connectFourWin = [0, 1, 0, 1, 0, 1, 0]
    /// The same one move short of the win.
    static let connectFourAlmostWon = [0, 1, 0, 1, 0, 1]

    /// A game as the server shows it to `me`. The version is one more than the
    /// number of moves unless a test says otherwise, as on the server where a
    /// new game starts at 1.
    static func game(
        kind: GameKind = .connectFour,
        id: UUID = gameID,
        gameNumber: Int = 1,
        first: UUID = me,
        moves: [Int] = [],
        finished: Bool = false,
        winner: UUID? = nil,
        version: Int? = nil,
        stake: String? = nil,
        myColor: LudoColor? = nil,
        partnerColor: LudoColor? = nil,
        photo: UUID? = nil,
        myWins: Int = 0,
        partnerWins: Int = 0,
        draws: Int = 0,
        gamesFinished: Int = 0
    ) -> RemoteBoardGame {
        RemoteBoardGame(
            id: id,
            kind: kind,
            gameNumber: gameNumber,
            status: finished ? .finished : .playing,
            version: version ?? moves.count + 1,
            firstUserID: first,
            moves: moves,
            turnUserID: finished ? nil : first,
            winnerUserID: winner,
            winLine: [],
            stake: stake,
            stakeByUserID: stake == nil ? nil : first,
            myColor: myColor,
            partnerColor: partnerColor,
            photoMediaAssetID: photo,
            myWins: myWins,
            partnerWins: partnerWins,
            draws: draws,
            gamesFinished: gamesFinished,
            previous: nil,
            startedAt: now,
            finishedAt: finished ? now : nil,
            turnStartedAt: now,
            updatedAt: now
        )
    }

    static func state(_ games: RemoteBoardGame..., user: UUID = me, epoch: String = "") -> RemoteBoardGames {
        RemoteBoardGames(
            userID: user,
            partnerUserID: user == me ? partner : me,
            coupleID: coupleID,
            dataEpoch: epoch,
            games: games
        )
    }

    /// A move that names the game's current version unless a test says otherwise.
    static func move(
        _ move: Int,
        on game: RemoteBoardGame,
        expectedVersion: Int? = nil,
        stake: String? = nil,
        ludoColor: LudoColor? = nil
    ) -> BoardGameMovePayload {
        BoardGameMovePayload(
            kind: game.kind,
            gameID: game.id,
            gameNumber: game.gameNumber,
            expectedVersion: expectedVersion ?? game.version,
            move: move,
            stake: stake,
            ludoColor: ludoColor,
            createdAt: now
        )
    }

    static func rematch(of game: RemoteBoardGame, expectedVersion: Int? = nil) -> BoardGameRematchPayload {
        BoardGameRematchPayload(
            kind: game.kind,
            gameID: game.id,
            expectedVersion: expectedVersion ?? game.version,
            createdAt: now
        )
    }

    /// An operation at a place in the queue. Equal times are ordered by the sequence.
    static func operation(sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: now)
    }
}
