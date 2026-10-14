import Foundation
import Testing
@testable import PaeoniaApp

/// The private stars of Exquisite corpse: `GameStars` with the corpse source shows
/// the cached state and stars with this phone's queued writes on top.
@MainActor
struct ExquisiteCorpseStarsTests {
    private let environment = ExquisiteCorpseDataEnvironment()
    private let figureID = ExquisiteCorpseFixture.figureID(1)

    private func makeStars() -> GameStars {
        let dependencies = GamesDependencies(
            gateway: UnavailableGamesGateway(),
            cache: InMemoryGamesCache(),
            pendingOperationStore: environment.pending,
            operationProvider: DeveloperScenarioOperationProvider(),
            drawingStore: environment.drawingStore,
            drawingTransfer: environment.transfer,
            makeLive: { _ in nil },
            now: { ExquisiteCorpseFixture.now }
        )
        return GameStars(source: .exquisiteCorpse(cache: environment.cache), dependencies: dependencies) {
            ExquisiteCorpseFixture.me
        }
    }

    private func saveState(starred: Bool) async {
        let state = ExquisiteCorpseFixture.state(
            game: ExquisiteCorpseFixture.game(figure: 2, partIndex: 0, turn: ExquisiteCorpseFixture.me),
            recent: [ExquisiteCorpseFixture.figure(1, starred: starred)]
        )
        await environment.cache.saveState(state, ownerUserID: ExquisiteCorpseFixture.me)
    }

    @Test func aStarShowsAtOnceAndWaitsInTheQueue() async throws {
        let stars = makeStars()

        await stars.setStarred(true, id: figureID)

        #expect(stars.isStarred(figureID))
        let queued = await environment.queued(.exquisiteCorpseStar)
        #expect(queued.count == 1)
        let payload = try JSONDecoder().decode(
            ExquisiteCorpseStarPayload.self,
            from: try #require(queued.first?.requestData)
        )
        #expect(payload == ExquisiteCorpseStarPayload(
            figureID: figureID,
            starred: true,
            createdAt: ExquisiteCorpseFixture.now
        ))
        #expect(queued.first?.idempotencyScope == "exquisite-corpse-star:\(figureID.uuidString.lowercased())")
    }

    @Test func theLastQueuedWriteOfAFigureWins() async throws {
        let stars = makeStars()
        await stars.setStarred(true, id: figureID)
        await stars.setStarred(false, id: figureID)

        let queued = await GameStars.queuedStars(
            from: environment.pending,
            ownerUserID: ExquisiteCorpseFixture.me,
            source: .exquisiteCorpse(cache: environment.cache)
        )

        #expect(queued == [figureID: false])
        #expect(!stars.isStarred(figureID))
    }

    @Test func aFigureStarredOnTheOtherPhoneShowsFromTheGameState() async {
        await saveState(starred: true)
        let stars = makeStars()

        await stars.reload()

        #expect(stars.isStarred(figureID))
    }

    @Test func aStarKeptFromAnEarlierAnswerShowsForAFigureTheStateNoLongerHas() async {
        let older = ExquisiteCorpseFixture.figureID(7)
        await environment.cache.saveStars([older: true], ownerUserID: ExquisiteCorpseFixture.me)
        let stars = makeStars()

        await stars.reload()

        #expect(stars.isStarred(older))
    }

    @Test func anUnsentChangeBeatsTheGameState() async {
        await saveState(starred: true)
        let stars = makeStars()
        await stars.reload()

        await stars.setStarred(false, id: figureID)

        #expect(!stars.isStarred(figureID))
    }

    @Test func aPageReadBeforeTheChangeNeverUndoesIt() async {
        let stars = makeStars()
        let mark = stars.changeMark
        await stars.setStarred(true, id: figureID)
        let other = ExquisiteCorpseFixture.figureID(2)

        await stars.applyServerStars([figureID: false, other: true], readSince: mark)

        #expect(stars.isStarred(figureID))
        #expect(stars.isStarred(other))
        let document = await environment.cache.document(ownerUserID: ExquisiteCorpseFixture.me)
        #expect(document.stars == [other: true])
    }
}
