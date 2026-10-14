import Foundation
import Testing
@testable import PaeoniaApp

/// What the Story Chain cache keeps and in which order it takes the answers it
/// gets. Each test runs on the in-memory cache and on the file cache.
struct StoryChainCacheTests {
    private typealias Fixture = StoryChainFixture

    private let me = Fixture.me

    /// A state of the current game at `version`, with the story it is writing.
    private func state(version: Int, turn: UUID = Fixture.me) -> RemoteStoryChainState {
        Fixture.state(
            Fixture.game(.writing, turn: turn, version: version),
            current: Fixture.story(.writing, lines: Fixture.lines(version, starter: Fixture.partner))
        )
    }

    private func eachCache(_ body: (any StoryChainCaching) async throws -> Void) async rethrows {
        try await body(InMemoryStoryChainCache())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(FileStoryChainCache(directoryURL: directory))
    }

    // MARK: Never older

    @Test func aLiveStateBehindTheOneKeptIsNotTaken() async {
        await eachCache { cache in
            await cache.saveState(state(version: 5), ownerUserID: me)

            // A live update sent before the move this phone already read arrives late.
            await cache.saveState(state(version: 3), ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).state == state(version: 5))
        }
    }

    @Test func aNewerLiveStateReplacesTheOneKept() async {
        await eachCache { cache in
            await cache.saveState(state(version: 3), ownerUserID: me)
            await cache.saveState(state(version: 4), ownerUserID: me)
            await cache.saveState(state(version: 4, turn: Fixture.partner), ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).state == state(version: 4, turn: Fixture.partner))
        }
    }

    @Test func aStateOfAnotherGameReplacesTheOneKeptWhateverItsVersion() async {
        await eachCache { cache in
            await cache.saveState(state(version: 9), ownerUserID: me)
            let other = Fixture.state(
                Fixture.game(.choosingOpening, turn: Fixture.me, current: nil, stories: 0, version: 1, id: UUID())
            )

            await cache.saveState(other, ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).state == other)
        }
    }

    @Test func aStateWithoutAGameIsNeverOlder() async {
        await eachCache { cache in
            await cache.saveState(state(version: 2), ownerUserID: me)
            let gone = Fixture.state(nil)

            await cache.saveState(gone, ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).state == gone)
        }
    }

    // MARK: One-shot reads

    @Test func aOneShotReadWithNoLiveWriteInBetweenIsSaved() async throws {
        let gateway = ScriptedStoryChainDataGateway()
        gateway.setStateToLoad(state(version: 2))
        try await eachCache { cache in
            let matched = try await cache.fetchState(from: gateway, ownerUserID: me)

            #expect(matched)
            #expect(await cache.document(ownerUserID: me).state == state(version: 2))
        }
    }

    @Test func aReadForAnotherPersonIsNotSaved() async throws {
        let gateway = ScriptedStoryChainDataGateway()
        gateway.setStateToLoad(state(version: 2))
        try await eachCache { cache in
            let matched = try await cache.fetchState(from: gateway, ownerUserID: UUID())

            #expect(!matched)
            #expect(await cache.document(ownerUserID: me).state == nil)
        }
    }

    @Test func aFailedReadThrowsAndSavesNothing() async {
        let gateway = ScriptedStoryChainDataGateway()
        gateway.fail("load")
        gateway.setStateToLoad(state(version: 2))
        await eachCache { cache in
            var didThrow = false
            do {
                _ = try await cache.fetchState(from: gateway, ownerUserID: me)
            } catch {
                didThrow = true
            }

            #expect(didThrow)
            #expect(await cache.document(ownerUserID: me).state == nil)
        }
    }

    @Test func anOlderReadNeverOverwritesALiveWrite() async {
        await eachCache { cache in
            let ticket = await cache.beginFetch()
            // The live feed writes while the one-shot read is on its way.
            await cache.saveState(state(version: 4), ownerUserID: me)

            let saved = await cache.saveFetchedState(state(version: 3), ownerUserID: me, ticket: ticket)

            #expect(!saved)
            #expect(await cache.document(ownerUserID: me).state == state(version: 4))
        }
    }

    @Test func aReadThatStartedBeforeALiveWriteIsSavedWhenItIsNewerByVersion() async {
        await eachCache { cache in
            let ticket = await cache.beginFetch()
            await cache.saveState(state(version: 3), ownerUserID: me)

            // The server moved on after the live update, so the read is the newer one.
            let saved = await cache.saveFetchedState(state(version: 4), ownerUserID: me, ticket: ticket)

            #expect(saved)
            #expect(await cache.document(ownerUserID: me).state == state(version: 4))
        }
    }

    @Test func anOlderReadThatAnswersLastDoesNotReplaceANewerOne() async {
        await eachCache { cache in
            let first = await cache.beginFetch()
            let second = await cache.beginFetch()
            await cache.saveFetchedState(state(version: 4), ownerUserID: me, ticket: second)

            let sameVersion = state(version: 4, turn: Fixture.partner)
            let savedOlder = await cache.saveFetchedState(sameVersion, ownerUserID: me, ticket: first)

            #expect(!savedOlder)
            #expect(await cache.document(ownerUserID: me).state == state(version: 4))
        }
    }

    @Test func aReadBehindTheKeptStateIsNotSavedEvenAsTheLatestRead() async {
        await eachCache { cache in
            await cache.saveState(state(version: 6), ownerUserID: me)
            let ticket = await cache.beginFetch()

            let saved = await cache.saveFetchedState(state(version: 5), ownerUserID: me, ticket: ticket)

            #expect(!saved)
            #expect(await cache.document(ownerUserID: me).state == state(version: 6))
        }
    }

    @Test func aReadThatWasOnItsWayDuringAPurgeIsNotSaved() async {
        await eachCache { cache in
            let ticket = await cache.beginFetch()
            await cache.clearAll()

            let saved = await cache.saveFetchedState(state(version: 2), ownerUserID: me, ticket: ticket)

            #expect(!saved)
            #expect(await cache.document(ownerUserID: me).state == nil)
        }
    }

    // MARK: People

    @Test func theDocumentOfOnePersonIsNeverReadByAnother() async {
        await eachCache { cache in
            await cache.saveState(state(version: 2), ownerUserID: me)
            await cache.saveHistoryFirstPage(
                RemoteStoryChainHistoryPage(stories: [storyChainHistoryItem(1)], nextBeforeStoryNumber: nil),
                ownerUserID: me
            )
            await cache.recordNotice(.moveRejected, ownerUserID: me)

            #expect(await cache.document(ownerUserID: Fixture.partner) == StoryChainLocalDocument())
            #expect(await cache.takeNotices(ownerUserID: Fixture.partner).isEmpty)
        }
    }

    @Test func clearAllRemovesEverything() async {
        await eachCache { cache in
            await cache.saveState(state(version: 2), ownerUserID: me)
            await cache.saveStars([UUID(): true], ownerUserID: me)
            await cache.recordNotice(.moveRejected, ownerUserID: me)

            await cache.clearAll()

            #expect(await cache.document(ownerUserID: me) == StoryChainLocalDocument())
        }
    }

    @Test func theInMemoryCacheStartsWithTheStateItIsGiven() async {
        let cache = InMemoryStoryChainCache(state: state(version: 2))

        #expect(await cache.document(ownerUserID: me).state == state(version: 2))
        #expect(await cache.document(ownerUserID: UUID()).state == nil)
    }

    // MARK: Notices

    @Test func aNoticeIsKeptOnceAndTakenOnce() async {
        await eachCache { cache in
            await cache.recordNotice(.moveRejected, ownerUserID: me)
            await cache.recordNotice(.moveRejected, ownerUserID: me)

            #expect(await cache.takeNotices(ownerUserID: me) == [.moveRejected])
            #expect(await cache.takeNotices(ownerUserID: me).isEmpty)
        }
    }

    // MARK: Stars

    @Test func aStarAnswerReachesTheStateTheFirstPageAndTheList() async {
        await eachCache { cache in
            let story = finishedStoryChainStory()
            let item = storyChainHistoryItem(1)
            await cache.saveState(finishedStoryChainState(story), ownerUserID: me)
            await cache.saveHistoryFirstPage(
                RemoteStoryChainHistoryPage(stories: [item], nextBeforeStoryNumber: nil),
                ownerUserID: me
            )

            await cache.saveStars([story.id: true, item.id: true], ownerUserID: me)

            let document = await cache.document(ownerUserID: me)
            #expect(document.state?.currentStory?.starredByMe == true)
            #expect(document.historyFirstPage?.stories.first?.starredByMe == true)
            #expect(document.stars == [story.id: true, item.id: true])
        }
    }

    @Test func aStoryThatLeavesTheStateKeepsItsStar() async {
        await eachCache { cache in
            let starred = finishedStoryChainStory(starred: true)
            await cache.saveState(finishedStoryChainState(starred, version: 1), ownerUserID: me)

            // The next story started, so the starred one is no longer in the state.
            let next = Fixture.story(.writing, id: Fixture.nextStoryID, number: 2)
            let later = Fixture.state(
                Fixture.game(.writing, turn: Fixture.me, current: next.id, stories: 2, version: 2),
                current: next
            )
            await cache.saveState(later, ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).stars[starred.id] == true)
        }
    }

    @Test func aStoryThatIsNotFinishedSaysNothingAboutStars() async {
        await eachCache { cache in
            await cache.saveState(state(version: 2), ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).stars.isEmpty)
        }
    }

    @Test func theStarsOfAStateBehindTheOneKeptAreNotTaken() async {
        await eachCache { cache in
            let starred = finishedStoryChainStory(starred: true)
            let unstarred = finishedStoryChainStory(starred: false)
            await cache.saveState(finishedStoryChainState(starred, version: 3), ownerUserID: me)

            await cache.saveState(finishedStoryChainState(unstarred, version: 2), ownerUserID: me)

            #expect(await cache.document(ownerUserID: me).stars[starred.id] == true)
        }
    }

    // MARK: On disk

    @Test func theFileCacheKeepsTheWholeDocumentBetweenLaunches() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storyID = UUID()
        let page = storyChainHistoryPage([2], next: 2)
        let first = FileStoryChainCache(directoryURL: directory)
        await first.saveState(state(version: 3), ownerUserID: me)
        await first.saveHistoryFirstPage(page, ownerUserID: me)
        await first.saveStars([storyID: true], ownerUserID: me)
        await first.recordNotice(.moveRejected, ownerUserID: me)

        let next = await FileStoryChainCache(directoryURL: directory).document(ownerUserID: me)

        #expect(next.state == state(version: 3))
        #expect(next.historyFirstPage == page)
        #expect(next.stars[storyID] == true)
        #expect(next.notices == [.moveRejected])
    }

    @Test func aFileMovedToAnotherPersonsNameReadsAsEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileStoryChainCache(directoryURL: directory)
        await cache.saveState(state(version: 3), ownerUserID: me)
        try FileManager.default.moveItem(
            at: directory.appendingPathComponent(me.uuidString.lowercased() + ".json"),
            to: directory.appendingPathComponent(Fixture.partner.uuidString.lowercased() + ".json")
        )

        #expect(await cache.document(ownerUserID: Fixture.partner) == StoryChainLocalDocument())
    }
}
