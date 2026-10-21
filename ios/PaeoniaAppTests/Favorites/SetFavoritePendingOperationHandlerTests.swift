import Foundation
import Testing
@testable import PaeoniaApp

/// The queued write: it goes in order, waits for what makes an item favoritable, and
/// tells the server and the cache what it took.
@MainActor
struct SetFavoritePendingOperationHandlerTests {
    private let owner = UUID()
    private let target = FavoriteTarget.gameRound(UUID())
    private let pending = InMemoryPendingSyncOperationRepository()
    private let cache = InMemoryFavoritesCache()
    private let gateway = RecordingFavoritesGateway()

    private func handler(gates: [FavoriteKind: any FavoriteSendGating] = [:]) -> SetFavoritePendingOperationHandler {
        SetFavoritePendingOperationHandler(gateway: gateway, cache: cache, gates: gates)
    }

    private func context() -> SyncContext {
        SyncContext(
            session: SyncSession(userID: owner),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: pending
        )
    }

    private func enqueue(_ favorited: Bool, sequence: Int64) async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner,
                operation: SyncClientOperation(
                    clientID: UUID(),
                    clientSequence: sequence,
                    localCreatedAt: Date(timeIntervalSince1970: Double(sequence))
                ),
                operationKind: .setFavorite,
                idempotencyScope: "favorites",
                requestData: try JSONEncoder().encode(
                    FavoriteWritePayload(target: target, favorited: favorited, createdAt: Date())
                )
            )
        )
    }

    private func queued() async throws -> [PendingSyncOperationSnapshot] {
        try await pending.inFlightOperations(ownerUserID: owner, kind: .setFavorite)
            .sorted { $0.operation.clientSequence < $1.operation.clientSequence }
    }

    // swiftlint:disable async_without_await
    private struct Wait: FavoriteSendGating {
        func mustWait(
            for _: FavoriteTarget,
            operation _: PendingSyncOperationSnapshot,
            context _: SyncContext
        ) async throws -> Bool {
            true
        }
    }
    // swiftlint:enable async_without_await

    @Test func sendingTellsTheServerAndKeepsItsAnswer() async throws {
        try await enqueue(true, sequence: 1)

        let result = try await handler().send(try #require(await queued().first), context: context())

        #expect(result == .succeeded)
        #expect(gateway.writes == [.init(target: target, favorited: true)])
        #expect(await cache.favorites(ownerUserID: owner).map(\.target) == [target])
    }

    @Test func aStarWaitsForAnEarlierWriteOfTheSameItem() async throws {
        try await enqueue(true, sequence: 1)
        try await enqueue(false, sequence: 2)

        let result = try await handler().send(try #require(await queued().last), context: context())

        #expect(result == .retry(after: nil))
        #expect(gateway.writes.isEmpty)
    }

    @Test func aStarWaitsWhenTheGameSaysTheItemIsNotFinished() async throws {
        try await enqueue(true, sequence: 1)

        let write = try #require(await queued().first)
        let result = try await handler(gates: [.gameRound: Wait()]).send(write, context: context())

        #expect(result == .retry(after: nil))
        #expect(gateway.writes.isEmpty)
    }

    @Test func takingAStarBackIgnoresTheGate() async throws {
        try await enqueue(false, sequence: 1)

        let write = try #require(await queued().first)
        let result = try await handler(gates: [.gameRound: Wait()]).send(write, context: context())

        #expect(result == .succeeded)
    }

    @Test func aFailedSendKeepsTheWriteForAnotherTry() async throws {
        try await enqueue(true, sequence: 1)
        gateway.error = .server(code: "55P03", message: "busy")

        await #expect(throws: PaeoniaConvexError.self) {
            _ = try await handler().send(try #require(await queued().first), context: context())
        }
        #expect(await cache.favorites(ownerUserID: owner).isEmpty)
        #expect(await cache.takeRefusalCount(ownerUserID: owner) == 0)
    }

    @Test func anItemThatCannotBeStarredDropsTheWriteAndCountsIt() async throws {
        try await enqueue(true, sequence: 1)
        gateway.error = .server(code: "23514", message: "this item cannot be saved")

        let result = try await handler().send(try #require(await queued().first), context: context())

        guard case .terminalFailure = result else {
            Issue.record("Expected the write to be dropped, got \(result)")
            return
        }
        #expect(await cache.takeRefusalCount(ownerUserID: owner) == 1)
    }
}

// swiftlint:disable async_without_await
/// Records the writes and fails the next one when told to.
final class RecordingFavoritesGateway: FavoritesGateway, @unchecked Sendable {
    struct Write: Equatable {
        var target: FavoriteTarget
        var favorited: Bool
    }

    private let lock = NSLock()
    private var recorded: [Write] = []
    private var failure: PaeoniaConvexError?

    var writes: [Write] {
        lock.withLock { recorded }
    }

    var error: PaeoniaConvexError? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    func setFavorite(_ target: FavoriteTarget, favorited: Bool) async throws {
        if let error { throw error }
        lock.withLock { recorded.append(Write(target: target, favorited: favorited)) }
    }

    func listFavorites() async throws -> [FavoriteRef] { [] }

    func summaries(of _: [FavoriteTarget]) async throws -> [FavoriteSummary] { [] }
}
// swiftlint:enable async_without_await
