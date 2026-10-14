import Foundation
import Testing
@testable import PaeoniaApp

/// What the board games cache keeps: which write wins, what the screens read
/// back, and what stays local.
struct BoardGamesCacheTests {
    private typealias Fixture = BoardGameDataFixture
    private let me = Fixture.me

    private func kept(_ cache: any BoardGamesCaching, _ kind: GameKind = .connectFour) async -> RemoteBoardGame? {
        await cache.document(ownerUserID: me).state?.game(kind)
    }

    // MARK: Live writes

    @Test func anOlderLiveStateIsIgnored() async {
        let cache = InMemoryBoardGamesCache(
            state: Fixture.state(Fixture.game(moves: [3, 4])),
            ownerUserID: me
        )

        await cache.saveState(Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)
        #expect(await kept(cache)?.version == 3)

        await cache.saveState(Fixture.state(Fixture.game(moves: [3, 4, 2])), ownerUserID: me)
        #expect(await kept(cache)?.version == 4)
    }

    @Test func aGameWithAnotherIDReplacesTheKeptOne() async {
        let cache = InMemoryBoardGamesCache(
            state: Fixture.state(Fixture.game(moves: [3, 4])),
            ownerUserID: me
        )

        await cache.saveState(Fixture.state(Fixture.game(id: Fixture.otherGameID)), ownerUserID: me)

        #expect(await kept(cache)?.id == Fixture.otherGameID)
        #expect(await kept(cache)?.version == 1)
    }

    @Test func eachKindOfGameKeepsItsOwnNewestVersion() async {
        let cache = InMemoryBoardGamesCache(
            state: Fixture.state(
                Fixture.game(kind: .connectFour, moves: [3, 4]),
                Fixture.game(kind: .dotsAndBoxes, id: Fixture.otherGameID)
            ),
            ownerUserID: me
        )

        // Connect Four is behind what is kept. Dots and Boxes is ahead, and
        // Ultimate Tic-Tac-Toe is new.
        await cache.saveState(
            Fixture.state(
                Fixture.game(kind: .connectFour, moves: [3]),
                Fixture.game(kind: .dotsAndBoxes, id: Fixture.otherGameID, moves: [0]),
                Fixture.game(kind: .ultimateTicTacToe, id: UUID())
            ),
            ownerUserID: me
        )

        #expect(await kept(cache, .connectFour)?.version == 3)
        #expect(await kept(cache, .dotsAndBoxes)?.version == 2)
        #expect(await kept(cache, .ultimateTicTacToe)?.version == 1)
    }

    @Test func aLiveStateWithoutAGameDoesNotRemoveIt() async {
        let cache = InMemoryBoardGamesCache(state: Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)

        await cache.saveState(Fixture.state(), ownerUserID: me)

        #expect(await kept(cache)?.version == 2)
    }

    @Test func aStateOfAnotherCoupleReplacesTheKeptState() async {
        let cache = InMemoryBoardGamesCache(state: Fixture.state(Fixture.game(moves: [3, 4])), ownerUserID: me)
        let newCouple = RemoteBoardGames(
            userID: me,
            partnerUserID: nil,
            coupleID: UUID(),
            games: [Fixture.game(id: Fixture.otherGameID)]
        )

        await cache.saveState(newCouple, ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).state == newCouple)
    }

    @Test func theAnswerToAMoveReplacesTheGameUnlessTheCachedOneIsNewer() async {
        let cache = InMemoryBoardGamesCache(state: Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)

        await cache.saveGame(Fixture.game(moves: [3, 4]), ownerUserID: me)
        #expect(await kept(cache)?.moves == [3, 4])

        await cache.saveGame(Fixture.game(moves: [3]), ownerUserID: me)
        #expect(await kept(cache)?.moves == [3, 4])
    }

    @Test func anAnswerWithNothingCachedIsNotKept() async {
        let cache = InMemoryBoardGamesCache()

        await cache.saveGame(Fixture.game(moves: [3]), ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).state == nil)
    }

    // MARK: One-shot reads

    @Test func aReadThatStartedBeforeALiveWriteDoesNotReplaceIt() async {
        let cache = InMemoryBoardGamesCache()
        let ticket = await cache.beginFetch()
        // The same version, but the live write no longer has the hidden photo,
        // such as when its memory was hidden.
        let live = Fixture.state(Fixture.game(kind: .dotsAndBoxes, moves: [0], photo: nil))
        let early = Fixture.state(Fixture.game(kind: .dotsAndBoxes, moves: [0], photo: UUID()))

        await cache.saveState(live, ownerUserID: me)
        let saved = await cache.saveFetchedState(early, ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).state == live)
    }

    @Test func aReadThatIsNewerIsSavedEvenAfterALiveWrite() async {
        let cache = InMemoryBoardGamesCache()
        let ticket = await cache.beginFetch()
        await cache.saveState(Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)

        let saved = await cache.saveFetchedState(
            Fixture.state(Fixture.game(moves: [3, 4])),
            ownerUserID: me,
            ticket: ticket
        )

        #expect(saved)
        #expect(await kept(cache)?.version == 3)
    }

    @Test func aReadThatStartedLaterBeatsOneThatStartedEarlier() async {
        let cache = InMemoryBoardGamesCache()
        let first = await cache.beginFetch()
        let second = await cache.beginFetch()
        let late = Fixture.state(Fixture.game(kind: .dotsAndBoxes, moves: [0], photo: UUID()))
        let early = Fixture.state(Fixture.game(kind: .dotsAndBoxes, moves: [0], photo: nil))

        #expect(await cache.saveFetchedState(late, ownerUserID: me, ticket: second))
        #expect(await !cache.saveFetchedState(early, ownerUserID: me, ticket: first))
        #expect(await cache.document(ownerUserID: me).state == late)
    }

    @Test func aReadThatStartedBeforeAPurgeIsNotSaved() async {
        let cache = InMemoryBoardGamesCache(state: Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)
        let ticket = await cache.beginFetch()

        await cache.clearAll()
        let saved = await cache.saveFetchedState(
            Fixture.state(Fixture.game(moves: [3])),
            ownerUserID: me,
            ticket: ticket
        )

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me) == BoardGamesLocalDocument())
    }

    @Test func aReadWithNothingCachedIsSaved() async {
        let cache = InMemoryBoardGamesCache()
        let ticket = await cache.beginFetch()

        let saved = await cache.saveFetchedState(Fixture.state(Fixture.game()), ownerUserID: me, ticket: ticket)

        #expect(saved)
        #expect(await kept(cache)?.version == 1)
    }

    @Test func fetchingTheStateCachesWhatTheServerSays() async throws {
        let gateway = ScriptedBoardGamesGateway()
        gateway.setStateToLoad(Fixture.state(Fixture.game(moves: [3])))
        let cache = InMemoryBoardGamesCache()

        let cached = try await cache.fetchState(from: gateway, ownerUserID: me)

        #expect(cached)
        #expect(await kept(cache)?.moves == [3])
    }

    @Test func fetchingTheStateForAnotherPersonCachesNothing() async throws {
        let gateway = ScriptedBoardGamesGateway()
        gateway.setStateToLoad(Fixture.state(Fixture.game(moves: [3]), user: Fixture.partner))
        let cache = InMemoryBoardGamesCache()

        let cached = try await cache.fetchState(from: gateway, ownerUserID: me)

        #expect(!cached)
        #expect(await cache.document(ownerUserID: me).state == nil)
    }

    @Test func aFailedFetchLeavesTheCacheAlone() async {
        let gateway = ScriptedBoardGamesGateway()
        gateway.fail("loadBoardGames")
        gateway.setStateToLoad(Fixture.state(Fixture.game()))
        let cache = InMemoryBoardGamesCache(state: Fixture.state(Fixture.game(moves: [3])), ownerUserID: me)

        await #expect(throws: ScriptedBoardGamesGateway.Failure.self) {
            try await cache.fetchState(from: gateway, ownerUserID: me)
        }
        #expect(await kept(cache)?.moves == [3])
    }
}
