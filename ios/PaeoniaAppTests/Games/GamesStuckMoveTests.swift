import Foundation
import Testing
@testable import PaeoniaApp

/// A run that tries every write, as when the retry delay has passed. The tests
/// would otherwise wait out the delays in real time.
private func triesEveryWriteContext(_ store: any PendingSyncOperationPersisting) -> SyncContext {
    SyncContext(
        session: SyncSession(userID: GameFixture.me),
        reason: .manualRefresh,
        stateStore: InMemorySyncStateRepository(),
        pendingOperationStore: store
    )
}

/// A guess the server keeps refusing used to stay in the queue forever. The
/// phone then showed "saved on this phone" while it was online, and a give up
/// behind it never left either. These tests run the real drain, the way the
/// first two-phone test hit it: the hosted server had not learned the speed
/// bonus fields yet, so it answered a correct guess with a bare "Server Error"
/// and took the wrong guesses before it.
@MainActor
struct GamesStuckMoveTests {
    private let environment = GamesTestEnvironment(
        state: GameFixture.state(
            settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.me),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true),
            choices: GameFixture.choices
        )
    )
    private let clientID = UUID()

    init() {
        // The server answers the read that follows each move it takes.
        environment.gateway.setStateToLoad(
            GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .guessing, turn: GameFixture.me),
                round: GameFixture.round(state: .guessing, drawer: GameFixture.partner, hasDrawing: true),
                choices: GameFixture.choices
            )
        )
    }
    private let serverError = PaeoniaConvexError.server(
        code: nil,
        message: "[Request ID: 245c8d4539293d42] Server Error"
    )

    private var drain: PendingSyncOperationDrainStream {
        PendingSyncOperationDrainStream(handlers: [
            SubmitGameGuessPendingOperationHandler(gateway: environment.gateway, cache: environment.cache),
            GiveUpGameRoundPendingOperationHandler(gateway: environment.gateway, cache: environment.cache),
        ])
    }

    private func enqueue(_ kind: SyncPendingOperationKind, _ payload: some Encodable, sequence: Int64) async throws {
        try await environment.pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: GameFixture.me,
                operation: SyncClientOperation(
                    clientID: clientID,
                    clientSequence: sequence,
                    localCreatedAt: GameFixture.now
                ),
                operationKind: kind,
                idempotencyScope: "games",
                requestData: try JSONEncoder().encode(payload)
            )
        )
    }

    private func queueWrongThenCorrectGuess() async throws {
        let wrong = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "cat",
            isCorrect: false,
            createdAt: GameFixture.now
        )
        let correct = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now,
            speedBonus: 2,
            solveMs: 4_000
        )
        try await enqueue(.submitGameGuess, wrong, sequence: 1)
        try await enqueue(.submitGameGuess, correct, sequence: 2)
    }

    private func runDrain() async throws {
        try await drain.push(context: triesEveryWriteContext(environment.pending))
    }

    private func pendingWork() async throws -> DrawAndGuessPendingWork {
        try #require(await DrawAndGuessPendingWork.load(from: environment.pending, ownerUserID: GameFixture.me))
    }

    private func phase(_ work: DrawAndGuessPendingWork) -> DrawAndGuessPhase {
        DrawAndGuessResolver(userID: GameFixture.me).resolve(
            state: GameFixture.state(
                settings: GameFixture.settings(),
                game: GameFixture.game(state: .guessing, turn: GameFixture.me),
                round: GameFixture.round(
                    state: .guessing,
                    drawer: GameFixture.partner,
                    hasDrawing: true,
                    resultSeenBy: [GameFixture.me]
                )
            ),
            pending: work,
            isPartnerDrawingLive: false
        ).phase
    }

    @Test func aCorrectGuessTheServerKeepsRefusingIsDroppedAndTheRoundStaysPlayable() async throws {
        environment.gateway.setGuessError(serverError, whenClaiming: true)
        try await queueWrongThenCorrectGuess()

        // The wrong guess lands. The correct one is refused and the phone
        // keeps it for now, and says it could not send it.
        try await runDrain()
        try await runDrain()
        let waiting = try await pendingWork()
        #expect(environment.gateway.guesses == ["cat"])
        #expect(waiting.guesses.map(\.guess) == ["umbrella"])
        #expect(waiting.lastSendFailedWhileOnline)
        #expect(phase(waiting) == .waitingToSync)

        // The third refusal ends it.
        try await runDrain()
        let after = try await pendingWork()
        #expect(after.isEmpty)
        #expect(phase(after) == .guessing)
        #expect(await environment.queued(.submitGameGuess).isEmpty)
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me) == [.moveRejected])
    }

    @Test func aGiveUpBehindTheRefusedGuessGoesOutOnceTheGuessIsDropped() async throws {
        environment.gateway.setGuessError(serverError)
        let correct = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "umbrella",
            isCorrect: true,
            createdAt: GameFixture.now
        )
        try await enqueue(.submitGameGuess, correct, sequence: 1)
        try await enqueue(
            .giveUpGameRound,
            GameGiveUpPayload(roundID: GameFixture.roundID, createdAt: GameFixture.now),
            sequence: 2
        )

        try await runDrain()
        try await runDrain()
        #expect(await environment.queued(.giveUpGameRound).count == 1)
        try await runDrain()

        #expect(await environment.queued(.submitGameGuess).isEmpty)
        #expect(await environment.queued(.giveUpGameRound).isEmpty)
        #expect(environment.gateway.calls.contains("giveUp"))
    }

    @Test func aLostConnectionNeverDropsAMove() async throws {
        environment.gateway.setGuessError(nil)
        environment.gateway.fail("guess")
        try await queueWrongThenCorrectGuess()

        for _ in 0..<6 {
            try await runDrain()
        }

        let work = try await pendingWork()
        #expect(work.guesses.count == 2)
    }

    @Test func aSignInOrAccessRefusalKeepsRetrying() async throws {
        environment.gateway.setGuessError(.server(code: "42501", message: "active entitled game access is required"))
        try await queueWrongThenCorrectGuess()

        for _ in 0..<6 {
            try await runDrain()
        }

        #expect(try await pendingWork().guesses.count == 2)
        #expect(await environment.cache.takeNotices(ownerUserID: GameFixture.me).isEmpty)
    }

    @Test func anOfflineFailureIsNotCountedAsAFailureWhileOnline() throws {
        let offline = snapshotWithError(String(describing: URLError(.notConnectedToInternet)))

        #expect(!offline.failedWhileOnline)
        #expect(!snapshotWithError("Retry later").failedWhileOnline)
        #expect(snapshotWithError(String(describing: serverError)).failedWhileOnline)
        #expect(!snapshotWithError(nil).failedWhileOnline)
    }

    /// The server took a guess, but the read after it failed. The guess stayed
    /// queued until the next sync a minute or more later, and the screen said
    /// "Saved on this phone" all that time. It now tries again within seconds.
    /// Offline, the replay itself fails and waits the usual time.
    @Test func aMoveWhoseReadBackFailedIsTriedAgainWithinSeconds() async throws {
        environment.gateway.fail("load")
        let wrong = GameGuessPayload(
            id: UUID(),
            roundID: GameFixture.roundID,
            guess: "cat",
            isCorrect: false,
            createdAt: GameFixture.now
        )
        try await enqueue(.submitGameGuess, wrong, sequence: 1)

        let firstTry = Date()
        try await runDrain()
        #expect(environment.gateway.guesses == ["cat"])
        #expect(await environment.queued(.submitGameGuess).count == 1)
        let soon = try #require(try await environment.pending.nextPendingOperationDate(
            ownerUserID: GameFixture.me,
            now: firstTry
        ))
        #expect(soon.timeIntervalSince(firstTry) <= 5)

        environment.gateway.fail("guess")
        let offlineTry = Date()
        try await runDrain()
        let later = try #require(try await environment.pending.nextPendingOperationDate(
            ownerUserID: GameFixture.me,
            now: offlineTry
        ))
        #expect(later.timeIntervalSince(offlineTry) >= 30)

        environment.gateway.unfail("guess")
        environment.gateway.unfail("load")
        try await runDrain()
        #expect(await environment.queued(.submitGameGuess).isEmpty)
    }

    private func snapshotWithError(_ error: String?, attemptCount: Int = 1) -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: GameFixture.me,
            operation: SyncClientOperation(clientID: clientID, clientSequence: 1),
            operationKind: .submitGameGuess,
            idempotencyScope: "games",
            requestHash: nil,
            requestData: nil,
            status: .failedRetryable,
            attemptCount: attemptCount,
            lastAttemptAt: nil,
            nextRetryAt: nil,
            lastError: error,
            completedAt: nil
        )
    }
}
