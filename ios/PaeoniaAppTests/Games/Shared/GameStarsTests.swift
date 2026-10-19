import Foundation
import Testing
@testable import PaeoniaApp

/// The private stars: a star shows at once, waits in the queue, keeps the last
/// choice, and sits on top of what the server said.
@MainActor
struct GameStarsTests {
    private let environment = GamesTestEnvironment(state: nil)
    private let roundID = UUID()
    private let clientID = UUID()

    private func makeStars(in other: GamesTestEnvironment? = nil, signedIn: Bool = true) -> GameStars {
        let env = other ?? environment
        return GameStars(source: .drawAndGuess(cache: env.cache), dependencies: env.dependencies()) {
            signedIn ? GameFixture.me : nil
        }
    }

    private func operation(_ sequence: Int64) -> SyncClientOperation {
        SyncClientOperation(clientID: clientID, clientSequence: sequence, localCreatedAt: GameFixture.now)
    }

    private func enqueueStar(_ starred: Bool, sequence: Int64, roundID: UUID? = nil) async throws {
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: operation(sequence),
                operationKind: .setGameRoundStar,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(
                    GameStarPayload(roundID: roundID ?? self.roundID, starred: starred, createdAt: GameFixture.now)
                )
            )
        )
    }

    // MARK: The store

    @Test func aStarShowsAtOnceAndWaitsInTheQueue() async throws {
        let stars = makeStars()

        await stars.setStarred(true, id: roundID)

        #expect(stars.isStarred(roundID))
        let queued = await environment.queued(.setGameRoundStar)
        #expect(queued.count == 1)
        let payload = try JSONDecoder().decode(GameStarPayload.self, from: try #require(queued.first?.requestData))
        #expect(payload.roundID == roundID)
        #expect(payload.starred)
        // The server was not called: the write leaves with the next sync.
        #expect(environment.gateway.starWrites.isEmpty)
    }

    @Test func theLastChoiceOfARoundWins() async {
        let stars = makeStars()

        await stars.setStarred(true, id: roundID)
        await stars.setStarred(false, id: roundID)

        #expect(!stars.isStarred(roundID))
        #expect(await environment.queued(.setGameRoundStar).count == 2)
    }

    @Test func anUnsentChangeBeatsTheServersValue() async {
        let stars = makeStars()
        await environment.cache.saveStars([roundID: true], ownerUserID: GameFixture.me)
        await stars.reload()

        await stars.setStarred(false, id: roundID)

        #expect(!stars.isStarred(roundID))
    }

    @Test func aStarWaitingInTheQueueSurvivesARelaunch() async throws {
        try await enqueueStar(true, sequence: 1)
        let afterRelaunch = makeStars()

        await afterRelaunch.reload()

        #expect(afterRelaunch.isStarred(roundID))
    }

    @Test func theLastQueuedWriteOfARoundWinsWhenReadingTheQueue() async throws {
        try await enqueueStar(true, sequence: 1)
        try await enqueueStar(false, sequence: 2)
        let other = UUID()
        try await enqueueStar(true, sequence: 3, roundID: other)

        let queued = await GameStars.queuedStars(
            from: environment.pending,
            ownerUserID: GameFixture.me,
            source: .drawAndGuess(cache: environment.cache)
        )

        #expect(queued == [roundID: false, other: true])
    }

    @Test func aPageReadBeforeTheChangeNeverUndoesIt() async {
        let stars = makeStars()
        let mark = stars.changeMark
        await stars.setStarred(true, id: roundID)
        let other = UUID()

        // A history page that was read before the star reached the server.
        await stars.applyServerStars([roundID: false, other: true], readSince: mark)

        #expect(stars.isStarred(roundID))
        #expect(stars.isStarred(other))
        let document = await environment.cache.document(ownerUserID: GameFixture.me)
        #expect(document.drawings?.starredRoundIDs == [other])
    }

    @Test func nothingIsStarredWithoutASignedInPerson() async {
        let stars = makeStars(signedIn: false)

        await stars.setStarred(true, id: roundID)

        #expect(!stars.isStarred(roundID))
        #expect(await environment.queued(.setGameRoundStar).isEmpty)
    }

    // MARK: The game state

    private func environmentWithRound(starred: Bool) -> (GamesTestEnvironment, UUID) {
        let round = GameFixture.round(
            state: .solved,
            drawer: GameFixture.partner,
            hasDrawing: true,
            starredByMe: starred
        )
        let state = GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
            recentRounds: [round]
        )
        return (GamesTestEnvironment(state: state), round.id)
    }

    @Test func theGameStateBeatsTheOlderCachedList() async {
        let (env, roundID) = environmentWithRound(starred: false)
        // The history cache lists the star from before the other phone removed it.
        await env.cache.saveStars([roundID: true], ownerUserID: GameFixture.me)
        let unstarred = GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)
        await env.cache.saveState(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .choosingWord, turn: GameFixture.me, roundID: nil),
                recentRounds: [unstarred]
            ),
            ownerUserID: GameFixture.me
        )
        let stars = makeStars(in: env)

        await stars.reload()

        #expect(!stars.isStarred(roundID))
    }

    // MARK: The queued write

    private func handler() -> SetGameRoundStarPendingOperationHandler {
        SetGameRoundStarPendingOperationHandler(gateway: environment.gateway, cache: environment.cache)
    }

    @Test func sendingAStarTellsTheServerAndKeepsItsAnswer() async throws {
        try await enqueueStar(true, sequence: 1)
        let queued = try #require(await environment.queued(.setGameRoundStar).first)

        let result = try await handler().send(queued, context: syncContext(environment.pending))

        #expect(result == .succeeded)
        #expect(environment.gateway.starWrites == [.init(roundID: roundID, starred: true)])
        let document = await environment.cache.document(ownerUserID: GameFixture.me)
        #expect(document.drawings?.starredRoundIDs == [roundID])
    }

    @Test func aStarWaitsForTheGuessThatEndsTheRound() async throws {
        let guess = GameGuessPayload(
            id: UUID(),
            roundID: roundID,
            guess: "UMBRELLA",
            isCorrect: true,
            createdAt: GameFixture.now
        )
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: operation(1),
                operationKind: .submitGameGuess,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(guess)
            )
        )
        try await enqueueStar(true, sequence: 2)
        let star = try #require(await environment.queued(.setGameRoundStar).first)

        let result = try await handler().send(star, context: syncContext(environment.pending))

        #expect(result == .retry(after: nil))
        #expect(environment.gateway.starWrites.isEmpty)
    }

    @Test func aStarWaitsForAnEarlierStarOfTheSameRound() async throws {
        try await enqueueStar(true, sequence: 1)
        try await enqueueStar(false, sequence: 2)
        let queued = await environment.queued(.setGameRoundStar)
        let later = try #require(queued.last)

        let result = try await handler().send(later, context: syncContext(environment.pending))

        #expect(result == .retry(after: nil))
        #expect(environment.gateway.starWrites.isEmpty)
    }

    @Test func aFailedSendKeepsTheWriteForAnotherTry() async throws {
        try await enqueueStar(true, sequence: 1)
        let queued = try #require(await environment.queued(.setGameRoundStar).first)
        environment.gateway.fail("star")

        await #expect(throws: ScriptedGamesGateway.Failure.self) {
            _ = try await handler().send(queued, context: syncContext(environment.pending))
        }
        let document = await environment.cache.document(ownerUserID: GameFixture.me)
        #expect(document.drawings == nil)
    }

    @Test func aRoundThatCannotBeStarredDropsTheWriteWithoutANotice() async throws {
        try await enqueueStar(true, sequence: 1)
        let queued = try #require(await environment.queued(.setGameRoundStar).first)
        environment.gateway.setStarError(.server(code: "23514", message: "round is not finished"))

        let result = try await handler().send(queued, context: syncContext(environment.pending))

        guard case .terminalFailure = result else {
            Issue.record("Expected the write to be dropped, got \(result)")
            return
        }
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me).isEmpty)
    }
}
