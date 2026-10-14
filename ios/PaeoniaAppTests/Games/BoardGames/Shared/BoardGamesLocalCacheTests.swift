import Foundation
import Testing
@testable import PaeoniaApp

/// The marks and the parts of the board games cache that stay on this phone,
/// and the cache on disk.
struct BoardGamesLocalCacheTests {
    private typealias Fixture = BoardGameDataFixture
    private let me = Fixture.me

    private func kept(_ cache: any BoardGamesCaching, _ kind: GameKind = .connectFour) async -> RemoteBoardGame? {
        await cache.document(ownerUserID: me).state?.game(kind)
    }

    // MARK: Marks

    private func marks(_ drawing: String?, partner: String? = nil) -> RemoteBoardGameMarks {
        RemoteBoardGameMarks(
            userID: me,
            mine: drawing.map { RemoteBoardGameMark(drawing: $0, updatedAt: Fixture.now) },
            partner: partner.map { RemoteBoardGameMark(drawing: $0, updatedAt: Fixture.now) }
        )
    }

    @Test func theLiveMarksWinOverAReadThatStartedBeforeThem() async {
        let cache = InMemoryBoardGamesCache()
        let ticket = await cache.beginMarksFetch()

        await cache.saveMarks(marks("bmV3"), ownerUserID: me)
        let saved = await cache.saveFetchedMarks(marks("b2xk"), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).marks == marks("bmV3"))
    }

    @Test func aClearedMarkIsKept() async {
        let cache = InMemoryBoardGamesCache()
        await cache.saveMarks(marks("bmV3", partner: "cGFydG5lcg=="), ownerUserID: me)

        await cache.saveMarks(marks(nil, partner: "cGFydG5lcg=="), ownerUserID: me)

        let saved = await cache.document(ownerUserID: me).marks
        #expect(saved?.mine == nil)
        #expect(saved?.partner?.drawing == "cGFydG5lcg==")
    }

    @Test func fetchingTheMarksCachesThem() async throws {
        let gateway = ScriptedBoardGamesGateway()
        gateway.setMarksToLoad(marks("bmV3"))
        let cache = InMemoryBoardGamesCache()

        let cached = try await cache.fetchMarks(from: gateway, ownerUserID: me)

        #expect(cached)
        #expect(await cache.document(ownerUserID: me).marks == marks("bmV3"))
    }

    // MARK: What stays local

    @Test func theShownPositionIsKeptPerKindAndPerPerson() async {
        let cache = InMemoryBoardGamesCache()
        let first = BoardGameShownPosition(gameNumber: 1, moveCount: 4)
        let second = BoardGameShownPosition(gameNumber: 2, moveCount: 0)

        await cache.markShown(first, kind: .connectFour, ownerUserID: me)
        await cache.markShown(first, kind: .dotsAndBoxes, ownerUserID: me)
        await cache.markShown(second, kind: .connectFour, ownerUserID: me)

        let document = await cache.document(ownerUserID: me)
        #expect(document.shownPosition(of: .connectFour) == second)
        #expect(document.shownPosition(of: .dotsAndBoxes) == first)
        #expect(document.shownPosition(of: .ultimateTicTacToe) == nil)
        #expect(await cache.document(ownerUserID: Fixture.partner).shown.isEmpty)
    }

    @Test func aNoticeIsTakenOnce() async {
        let cache = InMemoryBoardGamesCache()

        await cache.recordNotice(.moveRejected(.connectFour), ownerUserID: me)
        await cache.recordNotice(.moveRejected(.connectFour), ownerUserID: me)

        #expect(await cache.takeNotices(kind: .connectFour, ownerUserID: me) == [.moveRejected(.connectFour)])
        #expect(await cache.takeNotices(kind: .connectFour, ownerUserID: me).isEmpty)
    }

    @Test func aNoticeWaitsForTheBoardOfItsOwnGame() async {
        let cache = InMemoryBoardGamesCache()

        await cache.recordNotice(.moveRejected(.dotsAndBoxes), ownerUserID: me)

        #expect(await cache.takeNotices(kind: .connectFour, ownerUserID: me).isEmpty)
        #expect(await cache.takeNotices(kind: .dotsAndBoxes, ownerUserID: me) == [.moveRejected(.dotsAndBoxes)])
    }

    @Test func refusalsAreCountedPerOperation() async {
        let cache = InMemoryBoardGamesCache()
        let operation = UUID()

        #expect(await cache.recordUnexplainedRefusal(operationID: operation, ownerUserID: me) == 1)
        #expect(await cache.recordUnexplainedRefusal(operationID: UUID(), ownerUserID: me) == 1)
        #expect(await cache.recordUnexplainedRefusal(operationID: operation, ownerUserID: me) == 2)
    }

    @Test func clearingEverythingForgetsTheLocalPartToo() async {
        let cache = InMemoryBoardGamesCache(state: Fixture.state(Fixture.game()), ownerUserID: me)
        await cache.markShown(BoardGameShownPosition(gameNumber: 1, moveCount: 1), kind: .connectFour, ownerUserID: me)
        await cache.recordNotice(.moveRejected(.connectFour), ownerUserID: me)

        await cache.clearAll()

        #expect(await cache.document(ownerUserID: me) == BoardGamesLocalDocument())
    }

    // MARK: On disk

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardGamesCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func theFileCacheKeepsEverythingAcrossInstancesForTheOwnerOnly() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = Fixture.state(Fixture.game(moves: [3, 4], stake: "Loser makes coffee"))
        let position = BoardGameShownPosition(gameNumber: 1, moveCount: 2)
        let writer = FileBoardGamesCache(directoryURL: directory)

        await writer.saveState(state, ownerUserID: me)
        await writer.saveMarks(marks("bmV3"), ownerUserID: me)
        await writer.markShown(position, kind: .connectFour, ownerUserID: me)
        await writer.recordNotice(.moveRejected(.connectFour), ownerUserID: me)

        let reader = FileBoardGamesCache(directoryURL: directory)
        let document = await reader.document(ownerUserID: me)
        #expect(document.state == state)
        #expect(document.marks == marks("bmV3"))
        #expect(document.shownPosition(of: .connectFour) == position)
        #expect(document.notices == [.moveRejected(.connectFour)])
        #expect(await reader.document(ownerUserID: Fixture.partner) == BoardGamesLocalDocument())
    }

    @Test func theFileCacheAppliesTheSameWriteRulesAndPurgesFromDisk() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileBoardGamesCache(directoryURL: directory)
        await cache.saveState(Fixture.state(Fixture.game(moves: [3, 4])), ownerUserID: me)

        await cache.saveState(Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)
        #expect(await kept(cache)?.version == 3)

        let ticket = await cache.beginFetch()
        await cache.clearAll()
        let saved = await cache.saveFetchedState(
            Fixture.state(Fixture.game(moves: [3, 4])),
            ownerUserID: me,
            ticket: ticket
        )
        #expect(!saved)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await cache.document(ownerUserID: me) == BoardGamesLocalDocument())
    }
}
