import Foundation
import Testing
@testable import PaeoniaApp

/// The Mind Meld cache: it never takes a state that is behind the one it holds,
/// a one-shot read never beats a newer live write, and the file keeps one
/// person's data apart from another's.
struct MindMeldCacheTests {
    private let fixtures = MindMeldFixtures()
    private let me = GameFixture.me

    /// The same game at several versions: v1 has an open round 1, v2 has round 2 open.
    private var game: RemoteMindMeldGame {
        fixtures.game(rounds: [fixtures.open(1)])
    }

    private func state(_ game: RemoteMindMeldGame, previous: RemoteMindMeldGame? = nil) -> RemoteMindMeldState {
        fixtures.state(current: game, previous: previous)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MindMeldCacheTests-\(UUID().uuidString)")
    }

    // MARK: Order

    @Test func aLiveWriteOfAnOlderVersionIsRefused() async {
        let v1 = game
        let v2 = fixtures.moved(v1, version: 2)
        let v3 = fixtures.moved(v1, version: 3)
        let cache = InMemoryMindMeldCache()

        await cache.saveState(state(v2), ownerUserID: me)
        await cache.saveState(state(v1), ownerUserID: me)
        let kept = await cache.document(ownerUserID: me).state
        #expect(kept?.current?.version == 2)

        await cache.saveState(state(v3), ownerUserID: me)
        let newer = await cache.document(ownerUserID: me).state
        #expect(newer?.current?.version == 3)
    }

    @Test func aLowerGameNumberIsRefusedAndAHigherOneWinsWhateverItsVersion() async {
        let first = fixtures.moved(game, version: 9)
        let second = fixtures.game(number: 2, rounds: [fixtures.open(1)])
        let cache = InMemoryMindMeldCache()

        await cache.saveState(state(second), ownerUserID: me)
        await cache.saveState(state(first), ownerUserID: me)
        let kept = await cache.document(ownerUserID: me).state
        #expect(kept?.current?.id == second.id)

        let other = InMemoryMindMeldCache()
        await other.saveState(state(first), ownerUserID: me)
        await other.saveState(state(second), ownerUserID: me)
        let newer = await other.document(ownerUserID: me).state
        #expect(newer?.current?.id == second.id)
    }

    @Test func aLateStateThatStillListsAnEarlierGameIsOlder() async {
        let old = fixtures.game(.melded, rounds: [fixtures.revealed(1, "fish", "fish", outcome: .match)])
        let current = game
        let withPrevious = state(current, previous: old)
        let withoutPrevious = state(current)
        let cache = InMemoryMindMeldCache()

        // This person saw the earlier game's ending, and then a late state arrived.
        await cache.saveState(withoutPrevious, ownerUserID: me)
        await cache.saveState(withPrevious, ownerUserID: me)

        let kept = await cache.document(ownerUserID: me).state
        #expect(kept?.previous == nil)
    }

    @Test func aOneShotReadThatStartedBeforeALiveWriteIsRefused() async {
        let v1 = game
        let v2 = fixtures.moved(v1, version: 2)
        let cache = InMemoryMindMeldCache()
        await cache.saveState(state(v1), ownerUserID: me)

        let ticket = await cache.beginFetch()
        await cache.saveState(state(v2), ownerUserID: me)
        let saved = await cache.saveFetchedState(state(v1), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        let kept = await cache.document(ownerUserID: me).state
        #expect(kept?.current?.version == 2)
    }

    @Test func aOneShotReadThatIsNewerIsKeptEvenAfterALiveWrite() async {
        let v1 = game
        let v2 = fixtures.moved(v1, version: 2)
        let cache = InMemoryMindMeldCache()

        // The read saw the move, and the live write that landed meanwhile did not.
        let ticket = await cache.beginFetch()
        await cache.saveState(state(v1), ownerUserID: me)
        let saved = await cache.saveFetchedState(state(v2), ownerUserID: me, ticket: ticket)

        #expect(saved)
        let kept = await cache.document(ownerUserID: me).state
        #expect(kept?.current?.version == 2)
    }

    @Test func aLaterReadBeatsAnEarlierOne() async {
        let cache = InMemoryMindMeldCache()
        let first = await cache.beginFetch()
        let second = await cache.beginFetch()
        let v1 = game

        let savedSecond = await cache.saveFetchedState(state(v1), ownerUserID: me, ticket: second)
        let savedFirst = await cache.saveFetchedState(state(v1), ownerUserID: me, ticket: first)

        #expect(savedSecond)
        #expect(!savedFirst)
    }

    @Test func aStateOfAnotherPersonIsNotKept() async throws {
        let cache = InMemoryMindMeldCache()
        let ticket = await cache.beginFetch()

        await cache.saveState(state(game), ownerUserID: GameFixture.partner)
        let saved = await cache.saveFetchedState(state(game), ownerUserID: GameFixture.partner, ticket: ticket)

        #expect(!saved)
        let partnerDocument = await cache.document(ownerUserID: GameFixture.partner)
        #expect(partnerDocument.state == nil)
    }

    @Test func readingTheServerCachesTheAnswerForThePersonItIsFor() async throws {
        let gateway = ScriptedMindMeldGateway()
        gateway.setStateToLoad(state(game))
        let cache = InMemoryMindMeldCache()

        let forMe = try await cache.fetchState(from: gateway, ownerUserID: me)
        let forPartner = try await cache.fetchState(from: gateway, ownerUserID: GameFixture.partner)

        #expect(forMe)
        #expect(!forPartner)
        let partnerDocument = await cache.document(ownerUserID: GameFixture.partner)
        #expect(partnerDocument.state == nil)
    }

    // MARK: The file

    @Test func theFileKeepsWhatWasSavedAndKeepsPeopleApart() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = RemoteMindMeldHistoryPage(
            games: [fixtures.historyGame(number: 1)],
            nextBeforeGameNumber: nil,
            stats: RemoteMindMeldStats(melds: 1, fewestRounds: 3, games: 1)
        )
        let open = fixtures.open(1)
        let cache = FileMindMeldCache(directoryURL: directory)

        await cache.saveState(state(fixtures.game(rounds: [open])), ownerUserID: me)
        await cache.saveHistoryFirstPage(page, ownerUserID: me)
        await cache.recordRefusedWord(MindMeldRefusedWord(roundID: open.id, word: "ocean"), ownerUserID: me)

        // A new instance reads the same file.
        let reopened = FileMindMeldCache(directoryURL: directory)
        let document = await reopened.document(ownerUserID: me)
        #expect(document.state?.current?.rounds.first?.id == open.id)
        #expect(document.history == page)
        #expect(document.refusedWords == [MindMeldRefusedWord(roundID: open.id, word: "ocean")])
        let partnerDocument = await reopened.document(ownerUserID: GameFixture.partner)
        #expect(partnerDocument == MindMeldLocalDocument())
    }

    @Test func clearingRemovesEverythingAndStopsAReadInFlight() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileMindMeldCache(directoryURL: directory)
        await cache.saveState(state(game), ownerUserID: me)
        let ticket = await cache.beginFetch()

        await cache.clearAll()
        let saved = await cache.saveFetchedState(state(game), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        let document = await cache.document(ownerUserID: me)
        #expect(document == MindMeldLocalDocument())
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func refusedWordsAreTakenOnceAndEachRoundKeepsTheLatest() async {
        let cache = InMemoryMindMeldCache()
        let round = UUID()
        await cache.recordRefusedWord(MindMeldRefusedWord(roundID: round, word: "one"), ownerUserID: me)
        await cache.recordRefusedWord(MindMeldRefusedWord(roundID: round, word: "two"), ownerUserID: me)

        let taken = await cache.takeRefusedWords(ownerUserID: me)
        let again = await cache.takeRefusedWords(ownerUserID: me)

        #expect(taken == [MindMeldRefusedWord(roundID: round, word: "two")])
        #expect(again.isEmpty)
    }
}
