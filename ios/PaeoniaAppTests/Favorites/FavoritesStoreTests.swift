import Foundation
import Testing
@testable import PaeoniaApp

/// The private stars: a star shows at once, waits in the queue, keeps the last choice, and
/// sits on top of what the server said.
@MainActor
struct FavoritesStoreTests {
    private let owner = UUID()
    private let target = FavoriteTarget.answer(UUID())
    private let pending = InMemoryPendingSyncOperationRepository()
    private let cache = InMemoryFavoritesCache()

    private func makeStore(signedIn: Bool = true) async -> FavoritesStore {
        let store = FavoritesStore(
            cache: cache,
            pendingOperationStore: pending,
            operationProvider: SyncClientOperationFactory.shared,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            defaults: UserDefaults(suiteName: "FavoritesStoreTests-\(UUID().uuidString)") ?? .standard
        )
        await store.configure(ownerUserID: signedIn ? owner : nil)
        return store
    }

    private func enqueue(_ favorited: Bool, sequence: Int64, target: FavoriteTarget? = nil) async throws {
        try await pending.enqueue(
            PendingSyncOperationRequest(
                ownerUserID: owner,
                operation: SyncClientOperation(clientID: UUID(), clientSequence: sequence, localCreatedAt: Date()),
                operationKind: .setFavorite,
                idempotencyScope: "favorites",
                requestData: try JSONEncoder().encode(
                    FavoriteWritePayload(target: target ?? self.target, favorited: favorited, createdAt: Date())
                )
            )
        )
    }

    private func queued() async throws -> [PendingSyncOperationSnapshot] {
        try await pending.inFlightOperations(ownerUserID: owner, kind: .setFavorite)
    }

    @Test func aStarShowsAtOnceAndWaitsInTheQueue() async throws {
        let store = await makeStore()

        await store.setFavorite(true, target: target)

        #expect(store.isFavorite(target))
        let operations = try await queued()
        #expect(operations.count == 1)
        let data = try #require(operations.first?.requestData)
        let payload = try JSONDecoder().decode(FavoriteWritePayload.self, from: data)
        #expect(payload.target == target)
        #expect(payload.favorited)
    }

    @Test func theFirstStarSaysThatStarsArePrivateOnce() async {
        let store = await makeStore()

        await store.setFavorite(true, target: target)
        #expect(store.notice == .privateToYou)
        store.clearNotice()
        await store.setFavorite(true, target: .answer(UUID()))

        #expect(store.notice == nil)
    }

    @Test func theLastChoiceWins() async throws {
        let store = await makeStore()

        await store.setFavorite(true, target: target)
        await store.setFavorite(false, target: target)

        #expect(!store.isFavorite(target))
        #expect(try await queued().count == 2)
    }

    @Test func anUnsentChangeBeatsTheServersValue() async {
        await cache.save([FavoriteRef(target: target, createdAt: Date())], ownerUserID: owner)
        let store = await makeStore()
        #expect(store.isFavorite(target))

        await store.setFavorite(false, target: target)

        #expect(!store.isFavorite(target))
        #expect(store.allFavorites.isEmpty)
    }

    @Test func aStarWaitingInTheQueueSurvivesARelaunch() async throws {
        try await enqueue(true, sequence: 1)

        let afterRelaunch = await makeStore()

        #expect(afterRelaunch.isFavorite(target))
        #expect(afterRelaunch.allFavorites.map(\.target) == [target])
    }

    @Test func theLastQueuedWriteOfAnItemWinsWhenReadingTheQueue() async throws {
        let other = FavoriteTarget.question(UUID())
        try await enqueue(true, sequence: 1)
        try await enqueue(false, sequence: 2)
        try await enqueue(true, sequence: 3, target: other)

        let changes = await FavoritesStore.queuedChanges(from: pending, ownerUserID: owner)

        #expect(changes?.mapValues(\.favorited) == [target: false, other: true])
    }

    @Test func anItemTheServerNeverHeardOfComesFirstInTheList() async {
        let older = FavoriteTarget.question(UUID())
        await cache.save([FavoriteRef(target: older, createdAt: Date(timeIntervalSince1970: 1))], ownerUserID: owner)
        let store = await makeStore()

        await store.setFavorite(true, target: target)

        #expect(store.allFavorites.map(\.target) == [target, older])
    }

    @Test func aRefusalTheServerMadeForGoodIsToldOnce() async {
        await cache.recordRefusal(ownerUserID: owner)

        let store = await makeStore()

        #expect(store.notice == .refused)
        store.clearNotice()
        await store.reload()
        #expect(store.notice == nil)
    }

    @Test func nothingIsStarredWithoutASignedInPerson() async throws {
        let store = await makeStore(signedIn: false)

        await store.setFavorite(true, target: target)

        #expect(!store.isFavorite(target))
        #expect(try await queued().isEmpty)
    }
}
