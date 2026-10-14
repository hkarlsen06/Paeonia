import Foundation
import Testing
@testable import PaeoniaApp

/// What the Exquisite corpse cache keeps and which write wins when two answers cross.
struct ExquisiteCorpseCacheTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private let me = Fixture.me

    // MARK: Order of writes

    @Test func aLiveWriteBeatsAReadThatStartedBeforeIt() async {
        let cache = InMemoryExquisiteCorpseCache()
        let live = Fixture.state(version: 5, ideas: [Fixture.idea("a frog")])

        let ticket = await cache.beginFetch()
        await cache.saveState(live, ownerUserID: me)
        // Same version, so the read is not newer by what the server moves forward.
        let saved = await cache.saveFetchedState(Fixture.state(version: 5), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).state == live)
    }

    @Test func aReadThatIsNewerByVersionIsSavedAfterALiveWrite() async {
        let cache = InMemoryExquisiteCorpseCache()
        let newer = Fixture.state(version: 6)

        let ticket = await cache.beginFetch()
        await cache.saveState(Fixture.state(version: 5), ownerUserID: me)
        let saved = await cache.saveFetchedState(newer, ownerUserID: me, ticket: ticket)

        #expect(saved)
        #expect(await cache.document(ownerUserID: me).state == newer)
    }

    @Test func aReadWithNothingAheadOfItIsSaved() async {
        let cache = InMemoryExquisiteCorpseCache()
        let state = Fixture.state(version: 3)

        let ticket = await cache.beginFetch()
        let saved = await cache.saveFetchedState(state, ownerUserID: me, ticket: ticket)

        #expect(saved)
        #expect(await cache.document(ownerUserID: me).state == state)
    }

    @Test func anOlderReadThatAnswersLastDoesNotReplaceANewerOne() async {
        let cache = InMemoryExquisiteCorpseCache()
        let older = Fixture.state(version: 3)
        let newer = Fixture.state(version: 3, ideas: [Fixture.idea("a frog")])

        let first = await cache.beginFetch()
        let second = await cache.beginFetch()
        await cache.saveFetchedState(newer, ownerUserID: me, ticket: second)
        let savedOlder = await cache.saveFetchedState(older, ownerUserID: me, ticket: first)

        #expect(!savedOlder)
        #expect(await cache.document(ownerUserID: me).state == newer)
    }

    @Test func aReadThatWasOnItsWayDuringAPurgeIsNotSaved() async {
        let cache = InMemoryExquisiteCorpseCache()

        let ticket = await cache.beginFetch()
        await cache.clearAll()
        let saved = await cache.saveFetchedState(Fixture.state(version: 3), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).state == nil)
    }

    // MARK: Old states

    @Test func anOlderStateIsNeverSaved() async {
        let cache = InMemoryExquisiteCorpseCache()
        let kept = Fixture.state(version: 5)
        await cache.saveState(kept, ownerUserID: me)

        await cache.saveState(Fixture.state(version: 4), ownerUserID: me)
        let ticket = await cache.beginFetch()
        let saved = await cache.saveFetchedState(Fixture.state(version: 3), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).state == kept)
    }

    @Test func aLateStateWithoutTheRevealSeenTimeNeverReplacesOneWithIt() async {
        let cache = InMemoryExquisiteCorpseCache()
        func state(seen: Bool) -> RemoteExquisiteCorpseState {
            Fixture.state(version: 5, recent: [Fixture.figure(1, revealSeen: seen)])
        }
        await cache.saveState(state(seen: true), ownerUserID: me)

        // A live update sent before the mark landed arrives late.
        await cache.saveState(state(seen: false), ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).state == state(seen: true))
    }

    @Test func aStateWithTheRevealSeenTimeReplacesOneWithout() async {
        let cache = InMemoryExquisiteCorpseCache()
        func state(seen: Bool) -> RemoteExquisiteCorpseState {
            Fixture.state(version: 5, recent: [Fixture.figure(1, revealSeen: seen)])
        }
        await cache.saveState(state(seen: false), ownerUserID: me)

        await cache.saveState(state(seen: true), ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).state == state(seen: true))
    }

    @Test func aStarNeverDecidesWhichStateIsOlder() {
        let starred = Fixture.state(version: 5, recent: [Fixture.figure(1, starred: true)])
        let plain = Fixture.state(version: 5, recent: [Fixture.figure(1, starred: false)])

        #expect(!starred.isOlder(than: plain))
        #expect(!plain.isOlder(than: starred))
    }

    @Test func aStateOfAnotherGameIsNotOlder() {
        let other = Fixture.state(
            game: RemoteExquisiteCorpseGame(
                id: UUID(),
                turnUserID: Fixture.me,
                turnStartedAt: Fixture.now,
                figureID: nil,
                figureNumber: 1,
                partIndex: 0,
                figuresFinished: 0,
                version: 99,
                createdAt: Fixture.now,
                updatedAt: Fixture.now
            )
        )

        #expect(!Fixture.state(version: 1).isOlder(than: other))
        #expect(!other.isOlder(than: Fixture.state(version: 1)))
    }

    // MARK: Other people

    @Test func aStateForAnotherPersonIsNeverSaved() async {
        let cache = InMemoryExquisiteCorpseCache()
        let theirs = Fixture.state(Fixture.state(version: 5), readBy: Fixture.partner)

        await cache.saveState(theirs, ownerUserID: me)
        let ticket = await cache.beginFetch()
        let saved = await cache.saveFetchedState(theirs, ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).state == nil)
        #expect(await cache.document(ownerUserID: Fixture.partner).state == nil)
    }

    @Test func eachPersonReadsOnlyTheirOwnDocument() async {
        let cache = InMemoryExquisiteCorpseCache()
        await cache.saveState(Fixture.state(version: 5), ownerUserID: me)
        await cache.saveIdea("idea-a-frog", partID: UUID(), ownerUserID: me)

        let partnersDocument = await cache.document(ownerUserID: Fixture.partner)

        #expect(partnersDocument == ExquisiteCorpseLocalDocument())
    }

    // MARK: Fetching through the gateway

    @Test func fetchingCachesTheStateOfTheOwner() async throws {
        let cache = InMemoryExquisiteCorpseCache()
        let gateway = ScriptedExquisiteCorpseGateway()
        let state = Fixture.state(version: 4)
        gateway.setStateToLoad(state)

        let cached = try await cache.fetchState(from: gateway, ownerUserID: me)

        #expect(cached)
        #expect(await cache.document(ownerUserID: me).state == state)
    }

    @Test func fetchingAnswerForAnotherPersonIsNotCached() async throws {
        let cache = InMemoryExquisiteCorpseCache()
        let gateway = ScriptedExquisiteCorpseGateway()
        gateway.setStateToLoad(Fixture.state(Fixture.state(version: 4), readBy: Fixture.partner))

        let cached = try await cache.fetchState(from: gateway, ownerUserID: me)

        #expect(!cached)
        #expect(await cache.document(ownerUserID: me).state == nil)
    }

    @Test func aFailedFetchThrowsAndKeepsWhatWasCached() async {
        let cache = InMemoryExquisiteCorpseCache()
        let kept = Fixture.state(version: 4)
        await cache.saveState(kept, ownerUserID: me)
        let gateway = ScriptedExquisiteCorpseGateway()

        await #expect(throws: ScriptedExquisiteCorpseGateway.Failure.self) {
            _ = try await cache.fetchState(from: gateway, ownerUserID: me)
        }

        #expect(await cache.document(ownerUserID: me).state == kept)
    }
}

/// What the cache keeps besides the state: stars, ideas, notices and refusals, and the file on disk.
struct ExquisiteCorpseCacheContentTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private let me = Fixture.me

    // MARK: Stars

    @Test func starsPatchTheFiguresOfTheStateAndTheHistoryPage() async {
        let cache = InMemoryExquisiteCorpseCache()
        let state = Fixture.state(
            version: 5,
            current: Fixture.figure(3, parts: 2),
            recent: [Fixture.figure(2, starred: false), Fixture.figure(1, starred: true)]
        )
        let page = RemoteExquisiteCorpseHistoryPage(
            figures: [
                Fixture.figure(2, starred: false),
                Fixture.figure(1, starred: true),
                Fixture.figure(0, starred: false),
            ],
            nextBeforeFigureNumber: nil
        )
        await cache.saveState(state, ownerUserID: me)
        await cache.saveHistoryFirstPage(page, ownerUserID: me)
        let outsideTheState = UUID()

        await cache.saveStars(
            [Fixture.figureID(2): true, Fixture.figureID(1): false, outsideTheState: true],
            ownerUserID: me
        )

        let document = await cache.document(ownerUserID: me)
        #expect(document.stars == [Fixture.figureID(2): true, Fixture.figureID(1): false, outsideTheState: true])
        #expect(document.state?.recentFigures.map(\.starredByMe) == [true, false])
        #expect(document.state?.currentFigure == state.currentFigure)
        #expect(document.history?.figures.map(\.starredByMe) == [true, false, false])
        #expect(document.history?.nextBeforeFigureNumber == nil)
    }

    @Test func aLaterStarAnswerReplacesAnEarlierOne() async {
        let cache = InMemoryExquisiteCorpseCache()
        await cache.saveStars([Fixture.figureID(1): true], ownerUserID: me)

        await cache.saveStars([Fixture.figureID(1): false, Fixture.figureID(2): true], ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).stars == [Fixture.figureID(1): false, Fixture.figureID(2): true])
    }

    @Test func aHistoryPageGivesTheStarsItCarries() {
        let page = RemoteExquisiteCorpseHistoryPage(
            figures: [Fixture.figure(2, starred: true), Fixture.figure(1, starred: false)],
            nextBeforeFigureNumber: 1
        )

        #expect(page.starValues == [Fixture.figureID(2): true, Fixture.figureID(1): false])
    }

    // MARK: Ideas

    @Test func theIdeaOnTheChipIsKeptPerPartAndCanBeRemoved() async {
        let cache = InMemoryExquisiteCorpseCache()
        let head = UUID()
        let legs = UUID()

        await cache.saveIdea("head-grandma", partID: head, ownerUserID: me)
        await cache.saveIdea("legs-frog", partID: legs, ownerUserID: me)
        await cache.saveIdea("head-robot", partID: head, ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).ideas == [head: "head-robot", legs: "legs-frog"])

        await cache.saveIdea(nil, partID: head, ownerUserID: me)

        #expect(await cache.document(ownerUserID: me).ideas == [legs: "legs-frog"])
    }

    @Test func onlyTheLatest20IdeasStay() async {
        let cache = InMemoryExquisiteCorpseCache()
        let parts = (0..<21).map { _ in UUID() }
        for (index, part) in parts.enumerated() {
            await cache.saveIdea("idea-\(index)", partID: part, ownerUserID: me)
        }

        let ideas = await cache.document(ownerUserID: me).ideas

        #expect(ideas.count == 20)
        #expect(ideas[parts[0]] == nil)
        #expect(ideas[parts[1]] == "idea-1")
        #expect(ideas[parts[20]] == "idea-20")
    }

    @Test func choosingAnIdeaAgainMakesItTheNewestOne() async {
        let cache = InMemoryExquisiteCorpseCache()
        let parts = (0..<20).map { _ in UUID() }
        for (index, part) in parts.enumerated() {
            await cache.saveIdea("idea-\(index)", partID: part, ownerUserID: me)
        }

        // The oldest part gets a new idea, so the next part pushes out the second oldest.
        await cache.saveIdea("idea-new", partID: parts[0], ownerUserID: me)
        await cache.saveIdea("idea-extra", partID: UUID(), ownerUserID: me)

        let ideas = await cache.document(ownerUserID: me).ideas
        #expect(ideas[parts[0]] == "idea-new")
        #expect(ideas[parts[1]] == nil)
    }

    // MARK: Notices and refusals

    @Test func aNoticeIsKeptOnceAndForgottenWhenTaken() async {
        let cache = InMemoryExquisiteCorpseCache()

        await cache.recordNotice(.partRejected, ownerUserID: me)
        await cache.recordNotice(.partRejected, ownerUserID: me)
        await cache.recordNotice(.moveRejected, ownerUserID: me)

        #expect(await cache.takeNotices(ownerUserID: me) == [.partRejected, .moveRejected])
        #expect(await cache.takeNotices(ownerUserID: me).isEmpty)
        #expect(await cache.takeNotices(ownerUserID: Fixture.partner).isEmpty)
    }

    @Test func refusalsAreCountedPerOperation() async {
        let cache = InMemoryExquisiteCorpseCache()
        let first = UUID()
        let second = UUID()

        #expect(await cache.recordUnexplainedRefusal(operationID: first, ownerUserID: me) == 1)
        #expect(await cache.recordUnexplainedRefusal(operationID: first, ownerUserID: me) == 2)
        #expect(await cache.recordUnexplainedRefusal(operationID: second, ownerUserID: me) == 1)
    }

    @Test func clearingForgetsEverything() async {
        let cache = InMemoryExquisiteCorpseCache()
        await cache.saveState(Fixture.state(version: 5), ownerUserID: me)
        await cache.saveStars([Fixture.figureID(1): true], ownerUserID: me)
        await cache.saveIdea("head-robot", partID: UUID(), ownerUserID: me)
        await cache.recordNotice(.partRejected, ownerUserID: me)

        await cache.clearAll()

        #expect(await cache.document(ownerUserID: me) == ExquisiteCorpseLocalDocument())
    }

    // MARK: On disk

    @Test func theFileCacheKeepsEverythingAcrossLaunchesForTheOwnerOnly() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let part = UUID()
        let cache = FileExquisiteCorpseCache(directoryURL: directory)
        await cache.saveState(Fixture.state(version: 5, recent: [Fixture.figure(1)]), ownerUserID: me)
        await cache.saveHistoryFirstPage(
            RemoteExquisiteCorpseHistoryPage(figures: [Fixture.figure(1)], nextBeforeFigureNumber: nil),
            ownerUserID: me
        )
        await cache.saveStars([Fixture.figureID(1): true], ownerUserID: me)
        await cache.saveIdea("head-robot", partID: part, ownerUserID: me)
        await cache.recordNotice(.partRejected, ownerUserID: me)
        _ = await cache.recordUnexplainedRefusal(operationID: part, ownerUserID: me)

        let next = FileExquisiteCorpseCache(directoryURL: directory)
        let document = await next.document(ownerUserID: me)

        #expect(document.state?.game?.version == 5)
        #expect(document.state?.recentFigures.map(\.id) == [Fixture.figureID(1)])
        #expect(document.state?.recentFigures.map(\.starredByMe) == [true])
        #expect(document.history?.figures.map(\.id) == [Fixture.figureID(1)])
        #expect(document.stars == [Fixture.figureID(1): true])
        #expect(document.ideas == [part: "head-robot"])
        #expect(document.notices == [.partRejected])
        #expect(document.unexplainedRefusals == [part])
        #expect(await next.document(ownerUserID: Fixture.partner) == ExquisiteCorpseLocalDocument())
    }

    @Test func aFileCacheReadThatWasOnItsWayDuringAPurgeIsNotSaved() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileExquisiteCorpseCache(directoryURL: directory)
        await cache.saveState(Fixture.state(version: 5), ownerUserID: me)

        let ticket = await cache.beginFetch()
        await cache.clearAll()
        let saved = await cache.saveFetchedState(Fixture.state(version: 6), ownerUserID: me, ticket: ticket)

        #expect(!saved)
        #expect(await cache.document(ownerUserID: me).state == nil)
    }
}
