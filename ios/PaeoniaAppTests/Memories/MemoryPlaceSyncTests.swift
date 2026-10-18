import Foundation
import Testing
@testable import PaeoniaApp

/// How a memory's place is saved on the phone, queued for the server, and kept on disk.
struct MemoryPlaceSyncTests {
    private let bryggen = MemoryPlace.bryggen

    @Test func createMemoryQueuesAndShowsThePlace() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = makeService(pendingStore)
        let owner = UUID()

        let record = try await service.createMemory(
            ownerUserID: owner,
            coupleID: UUID(),
            title: "Rain all weekend",
            memoryDate: "2026-04-18",
            noteBody: "Cafés",
            place: bryggen,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
        )

        #expect(record.snapshot.place == bryggen)
        let queued = try await pendingStore.inFlightOperations(ownerUserID: owner, kind: .createMemory)
        let payload = try #require(queued.first?.requestData).decoded(as: CreateMemoryOperationPayload.self)
        #expect(payload.place == bryggen)
    }

    @Test func setMemoryPlaceQueuesItsOwnWriteAndKeepsTheRevision() async throws {
        let pendingStore = InMemoryPendingSyncOperationRepository()
        let service = makeService(pendingStore)
        let owner = UUID()
        let created = try await service.createMemory(
            ownerUserID: owner,
            coupleID: UUID(),
            title: "Trip",
            memoryDate: "2026-04-18",
            noteBody: "Note",
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
        )

        let placed = try await service.setMemoryPlace(
            ownerUserID: owner,
            memoryID: created.snapshot.memoryID,
            place: bryggen,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 2)
        )
        #expect(placed.snapshot.place == bryggen)
        #expect(placed.snapshot.revision == created.snapshot.revision)
        #expect(placed.syncStatus == .dirty)

        let cleared = try await service.setMemoryPlace(
            ownerUserID: owner,
            memoryID: created.snapshot.memoryID,
            place: nil,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 3)
        )
        #expect(cleared.snapshot.place == nil)

        let payloads = try await pendingStore
            .inFlightOperations(ownerUserID: owner, kind: .setMemoryPlace)
            .map { try #require($0.requestData).decoded(as: SetMemoryPlaceOperationPayload.self) }
        #expect(payloads.map(\.place) == [bryggen, nil])
    }

    private func makeService(_ pendingStore: InMemoryPendingSyncOperationRepository) -> MemoryDataService {
        MemoryDataService(memoryStore: InMemoryMemoryRecordRepository(), pendingOperationStore: pendingStore)
    }

    @Test func aPlaceForADeletedMemoryIsRefusedOnThePhone() async throws {
        let service = MemoryDataService(
            memoryStore: InMemoryMemoryRecordRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        await #expect(throws: MemoryDataServiceError.missingMemory) {
            try await service.setMemoryPlace(
                ownerUserID: UUID(),
                memoryID: UUID(),
                place: bryggen,
                operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
            )
        }
    }

    /// Clearing a place must send `null`, which the server reads as "no place".
    @Test func clearingAPlaceSendsNull() throws {
        let request = SetMemoryPlaceRequest(
            payload: SetMemoryPlaceOperationPayload(memoryID: UUID(), place: nil),
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
        )
        let json = try #require(String(data: try JSONEncoder().encode(request), encoding: .utf8))
        #expect(json.contains("\"p_place\":null"))
    }

    @Test func theServerRowDecodesItsPlace() throws {
        let json = #"{"name":"Bryggen","latitude":60.3975,"longitude":5.3245,"city":"Bergen","country_code":"NO"}"#
        #expect(try JSONDecoder().decode(MemoryPlace.self, from: Data(json.utf8)) == bryggen)
    }

    @Test func theLocalStoreKeepsThePlace() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let repository = SwiftDataMemoryRecordRepository(container: store.container)
        let service = MemoryDataService(
            memoryStore: repository,
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
        let owner = UUID()
        let created = try await service.createMemory(
            ownerUserID: owner,
            coupleID: UUID(),
            title: "Trip",
            memoryDate: "2026-04-18",
            noteBody: "Note",
            place: bryggen,
            operation: SyncClientOperation(clientID: UUID(), clientSequence: 1)
        )

        let loaded = try await repository.load(ownerUserID: owner, memoryID: created.snapshot.memoryID)
        #expect(loaded?.snapshot.place == bryggen)
    }
}

@MainActor
struct MemoriesViewModelPlaceTests {
    private let bryggen = MemoryPlace.bryggen

    @Test func anEditThatChangesThePlaceSendsIt() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "Note", photos: [])
        let record = try #require(env.viewModel.timeline.flatMap(\.memories).first)

        let saved = await env.viewModel.saveEdits(edit(of: record, place: bryggen))

        #expect(saved)
        #expect(env.viewModel.timeline.flatMap(\.memories).first?.snapshot.place == bryggen)
        #expect(try await queued(.setMemoryPlace, in: env).count == 1)
        // The title and date didn't change, so no update was queued.
        #expect(try await queued(.updateMemory, in: env).isEmpty)
    }

    /// The partner set a place while this person had the form open without touching it.
    @Test func anEditThatLeavesThePlaceAloneKeepsThePartnersPlace() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(title: "Trip", date: "2026-06-30", note: "Note", photos: [])
        let openedWith = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        await env.viewModel.setPlace(bryggen, forMemory: openedWith.snapshot.memoryID)

        let saved = await env.viewModel.saveEdits(
            edit(of: openedWith, title: "New title", place: openedWith.snapshot.place)
        )

        #expect(saved)
        let current = try #require(env.viewModel.timeline.flatMap(\.memories).first)
        #expect(current.snapshot.place == bryggen)
        #expect(current.snapshot.title == "New title")
        #expect(try await queued(.setMemoryPlace, in: env).count == 1)
    }

    @Test func createWithAPlaceShowsItOnTheMap() async throws {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)
        _ = await env.viewModel.createMemory(
            title: "Placed",
            date: "2026-06-30",
            note: "Note",
            photos: [],
            place: bryggen
        )
        _ = await env.viewModel.createMemory(title: "Not placed", date: "2026-06-29", note: "Note", photos: [])

        #expect(env.viewModel.mapContent.placed.map(\.title) == ["Placed"])
        #expect(env.viewModel.mapContent.unplaced.map(\.snapshot.title) == ["Not placed"])
        #expect(env.viewModel.knownPlaces == [bryggen])
    }

    @Test func setPlaceForADeletedMemoryShowsWhatHappened() async {
        let env = makeEnvironment()
        await env.viewModel.configure(currentUserID: env.userID, coupleID: env.coupleID)

        let saved = await env.viewModel.setPlace(bryggen, forMemory: UUID())

        #expect(!saved)
        #expect(env.viewModel.notice == .memoryRemoved)
    }

    @Test func theDraftKeepsItsPlace() {
        let store = makeIsolatedMemoryDraftStore()
        let userID = UUID()
        store.setDraft(MemoryDraft(place: bryggen), for: userID)
        #expect(store.draft(for: userID)?.place == bryggen)
    }

    private func queued(
        _ kind: SyncPendingOperationKind,
        in env: MemoriesTestEnvironment
    ) async throws -> [PendingSyncOperationSnapshot] {
        try await env.pendingStore.inFlightOperations(ownerUserID: env.userID, kind: kind)
    }

    private func edit(of record: MemoryRecord, title: String = "Trip", place: MemoryPlace?) -> MemoryEdit {
        MemoryEdit(
            base: record,
            title: title,
            date: record.snapshot.memoryDate,
            note: record.snapshot.ownNote?.body ?? "",
            newPhotos: [],
            removedMedia: [],
            place: place
        )
    }

    private func makeEnvironment() -> MemoriesTestEnvironment {
        makeMemoriesTestEnvironment(
            uploader: nil,
            imageProvider: nil,
            photoSaver: MemoryTestPhotoSaver(result: .saved),
            draftStore: nil
        )
    }
}
