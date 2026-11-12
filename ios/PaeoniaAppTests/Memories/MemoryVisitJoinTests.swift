import Foundation
import Testing
@testable import PaeoniaApp

struct MemoryVisitJoinTests {
    let me = UUID()
    let partner = UUID()
    let coupleID = UUID()
    let visitID = UUID()
    let waitingID = UUID()
    let joinedID = UUID()
    let myPhoto = UUID()
    let partnerPhoto = UUID()

    @Test func aTitleOrDateEditGoesIntoTheirNoteAndNeverReachesThePartnersTitleOrDate() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.updateMemory(
            ownerUserID: me, memoryID: waitingID, expectedRevision: 1, title: "Bergen days",
            memoryDate: "2026-07-03", operation: phone.nextOperation()
        )

        try await phone.drain()

        let server = phone.server
        #expect(await server.title == "Trip")
        #expect(await server.date == "2026-07-01")
        #expect(await server.notes[me]?.body == "Bergen days\n\nRain")
        #expect(await server.notes[partner]?.body == "Partner's note")
        #expect(try await phone.isSettled())
    }

    @Test func aPhotoDescriptionEditReachesTheirPhotoAndLeavesTheTitleAlone() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.updateMemory(
            ownerUserID: me, memoryID: waitingID, expectedRevision: 1, title: "Bergen", memoryDate: "2026-06-30",
            photoDescriptions: [MemoryPhotoDescription(mediaAssetID: myPhoto, text: "Fish market")],
            operation: phone.nextOperation()
        )

        try await phone.drain()

        #expect(await phone.server.photos.first { $0.assetID == myPhoto }?.text == "Fish market")
        #expect(await phone.server.title == "Trip")
        #expect(await phone.server.date == "2026-07-01")
    }

    @Test func aPlaceSetWhileWaitingNeverReplacesThePartnersPlace() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.setMemoryPlace(
            ownerUserID: me, memoryID: waitingID, place: Self.place("Ullevål"), operation: phone.nextOperation()
        )

        try await phone.drain()

        #expect(await phone.server.place?.name == "Fløyen")
        #expect(await phone.server.placeWrites == 0)
        #expect(try await phone.isSettled())
    }

    @Test func aNoteEditKeepsTheirTitleOnItsFirstLine() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.upsertMemoryNote(
            ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Rain all week",
            operation: phone.nextOperation()
        )

        try await phone.drain()

        #expect(await phone.server.notes[me]?.body == "Bergen\n\nRain all week")
        #expect(await phone.server.notes[partner]?.body == "Partner's note")
    }

    @Test func aPhotoAddedWhileWaitingEndsOnTheJoinedMemoryAsTheirs() async throws {
        let phone = try await phoneWithWaitingMemory()
        let added = Self.photo(owner: me, sortOrder: 2)
        _ = try await phone.service.attachMemoryMedia(
            ownerUserID: me, memoryID: waitingID, optimisticMedia: [added], operation: phone.nextOperation()
        )

        try await phone.drain()

        #expect(await phone.server.visiblePhotos(of: me) == [myPhoto, added.mediaAssetID])
        #expect(await phone.server.visiblePhotos(of: partner) == [partnerPhoto])
    }

    @Test func aPhotoRemovedWhileWaitingLeavesTheJoinedMemoryAndAnAddedAndRemovedOneIsNeverSent() async throws {
        let phone = try await phoneWithWaitingMemory()
        let added = Self.photo(owner: me, sortOrder: 2)
        _ = try await phone.service.attachMemoryMedia(
            ownerUserID: me, memoryID: waitingID, optimisticMedia: [added], operation: phone.nextOperation()
        )
        for media in [myPhoto, added.memoryMediaID] {
            _ = try await phone.service.removeMemoryMedia(
                ownerUserID: me, memoryID: waitingID, memoryMediaID: media, operation: phone.nextOperation()
            )
        }

        try await phone.drain()

        #expect(await phone.server.visiblePhotos(of: me).isEmpty)
        #expect(await phone.server.visiblePhotos(of: partner) == [partnerPhoto])
        #expect(await phone.server.attachedAssetIDs.isEmpty)
    }

    @Test func aDeleteWhileWaitingTakesTheirNoteAndPhotosOffAndKeepsThePartnersMemory() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.hideMemory(
            ownerUserID: me, memoryID: waitingID, expectedRevision: 1, operation: phone.nextOperation()
        )

        try await phone.drain()

        let server = phone.server
        #expect(await server.isDeleted == false)
        #expect(await server.notes[me] == nil)
        #expect(await server.visiblePhotos(of: me).isEmpty)
        #expect(await server.notes[partner]?.body == "Partner's note")
        #expect(await server.visiblePhotos(of: partner) == [partnerPhoto])
        #expect(try await phone.store.load(ownerUserID: me, memoryID: waitingID) == nil)
        #expect(try await phone.isSettled())
    }

    @Test func theJoinedMemoryShowsTheirLatestNoteAndPhotosOnThisPhoneBeforeItIsSent() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.upsertMemoryNote(
            ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Rain all week",
            operation: phone.nextOperation()
        )
        let create = try #require(try await phone.queued(.createMemory).first)

        _ = try await phone.createHandler.send(create, context: phone.context)

        #expect(try await phone.store.load(ownerUserID: me, memoryID: waitingID) == nil)
        let joined = try #require(try await phone.store.load(ownerUserID: me, memoryID: joinedID))
        #expect(joined.snapshot.title == "Trip")
        #expect(joined.snapshot.ownNote?.body == "Bergen\n\nRain all week")
        #expect(joined.snapshot.media.filter(\.isVisible).map(\.mediaAssetID).contains(myPhoto))
    }

    @Test func aJoinThatRunsAgainAfterACrashQueuesEachWriteOnce() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.upsertMemoryNote(
            ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Rain all week",
            operation: phone.nextOperation()
        )
        let create = try #require(try await phone.queued(.createMemory).first)
        let crashing = HookedPendingStore(phone.pending) { throw HookedPendingStore.Crash() }
        let context = SyncContext(
            session: SyncSession(userID: me), reason: .manualRefresh, pendingOperationStore: crashing
        )

        await #expect(throws: HookedPendingStore.Crash.self) {
            _ = try await phone.createHandler.send(create, context: context)
        }
        _ = try await phone.createHandler.send(create, context: context)

        let notes = try await phone.queued(.upsertMemoryNote)
        #expect(notes.count == 1)
        #expect(notes.allSatisfy { MemoryPendingOperationRefresh.memoryID(in: $0.requestData ?? Data()) == joinedID })
    }

    @Test func aNoteSavedWhileTheJoinReadsTheServerReachesTheJoinedMemory() async throws {
        let phone = try await phoneWithWaitingMemory()
        let (service, me, waitingID) = (phone.service, me, waitingID)
        let operation = phone.nextOperation()
        await phone.server.runDuringNextLoad {
            _ = try await service.upsertMemoryNote(
                ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Typed during the join",
                operation: operation
            )
        }

        try await phone.drain()

        #expect(await phone.server.notes[me]?.body == "Bergen\n\nTyped during the join")
        let joined = try await phone.store.load(ownerUserID: me, memoryID: joinedID)
        #expect(joined?.snapshot.ownNote?.body == "Bergen\n\nTyped during the join")
        #expect(try await phone.isSettled())
    }

    @Test func aNoteSavedWhileTheJoinMovesTheWritesWaitsAndQueuesNothingOnTheRemovedMemory() async throws {
        let phone = try await phoneWithWaitingMemory()
        _ = try await phone.service.upsertMemoryNote(
            ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Rain all week",
            operation: phone.nextOperation()
        )
        let (service, me, waitingID) = (phone.service, me, waitingID)
        let operation = phone.nextOperation()
        let late = LateEdit()
        let pending = HookedPendingStore(phone.pending) {
            await late.start {
                _ = try await service.upsertMemoryNote(
                    ownerUserID: me, memoryID: waitingID, expectedRevision: nil, body: "Typed while it moves",
                    operation: operation
                )
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        try await phone.drain(context: SyncContext(
            session: SyncSession(userID: me), reason: .manualRefresh, pendingOperationStore: pending
        ))

        await #expect(throws: MemoryDataServiceError.missingMemory) { try await late.finish() }
        var onRemovedMemory: [PendingSyncOperationSnapshot] = []
        for kind in MemoryPendingOperationRefresh.memoryWriteKinds {
            onRemovedMemory += try await phone.queued(kind)
                .filter { MemoryPendingOperationRefresh.memoryID(in: $0.requestData ?? Data()) == waitingID }
        }
        #expect(onRemovedMemory.isEmpty)
        #expect(try await phone.store.load(ownerUserID: me, memoryID: waitingID) == nil)
    }

    @Test func aRefusedPhotoTakesItsDescriptionWithItAndLaterEditsStillGo() async throws {
        let phone = try await phoneWithWaitingMemory()
        let added = Self.photo(owner: me, sortOrder: 2)
        _ = try await phone.service.attachMemoryMedia(
            ownerUserID: me, memoryID: waitingID, optimisticMedia: [added], operation: phone.nextOperation()
        )
        _ = try await phone.service.updateMemory(
            ownerUserID: me, memoryID: waitingID, expectedRevision: 1, title: "Bergen", memoryDate: "2026-06-30",
            photoDescriptions: [MemoryPhotoDescription(mediaAssetID: added.mediaAssetID, text: "The pier")],
            operation: phone.nextOperation()
        )
        await phone.server.refuseAttach()
        try await phone.drain()

        let joined = try #require(try await phone.store.load(ownerUserID: me, memoryID: joinedID))
        _ = try await phone.service.updateMemory(
            ownerUserID: me, memoryID: joinedID, expectedRevision: joined.snapshot.revision, title: "Trip to Bergen",
            memoryDate: joined.snapshot.memoryDate, operation: phone.nextOperation()
        )
        try await phone.drain()

        #expect(await phone.server.title == "Trip to Bergen")
        #expect(await phone.server.visiblePhotos(of: me) == [myPhoto])
        #expect(try await phone.isSettled())
    }
}

// MARK: - Fixtures

extension MemoryVisitJoinTests {
    func phoneWithWaitingMemory() async throws -> Phone {
        let server = VisitJoinServer(me: me, partner: partner, coupleID: coupleID, joinedID: joinedID, visitID: visitID)
        await server.seedPartner(photo: partnerPhoto)
        let phone = Phone(me: me, server: server)
        _ = try await phone.service.createMemory(
            ownerUserID: me, coupleID: coupleID, memoryID: waitingID, title: "Bergen", memoryDate: "2026-06-30",
            noteBody: "Rain", optimisticMedia: [Self.photo(id: myPhoto, owner: me, sortOrder: 1)],
            place: Self.place("Bryggen"), visitID: visitID, operation: phone.nextOperation()
        )
        return phone
    }

    static func photo(id: UUID = UUID(), owner: UUID, sortOrder: Int) -> MemoryMediaSnapshot {
        MemoryMediaSnapshot(
            memoryMediaID: id, mediaAssetID: id, ownerUserID: owner, sortOrder: sortOrder,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }

    static func place(_ name: String) -> MemoryPlace {
        MemoryPlace(name: name, latitude: 60.39, longitude: 5.32, city: "Bergen", countryCode: "NO")
    }

    final class Phone: Sendable {
        let me: UUID
        let server: VisitJoinServer
        let store = InMemoryMemoryRecordRepository()
        let pending = InMemoryPendingSyncOperationRepository()
        let service: MemoryDataService
        private let clientID = UUID()
        private let sequence = Counter()

        init(me: UUID, server: VisitJoinServer) {
            self.me = me
            self.server = server
            service = MemoryDataService(memoryStore: store, pendingOperationStore: pending)
        }

        var context: SyncContext {
            SyncContext(session: SyncSession(userID: me), reason: .manualRefresh, pendingOperationStore: pending)
        }

        var createHandler: CreateMemoryPendingOperationHandler {
            CreateMemoryPendingOperationHandler(gateway: server, memoryStore: store)
        }

        func nextOperation() -> SyncClientOperation {
            SyncClientOperation(clientID: clientID, clientSequence: sequence.next())
        }

        func queued(_ kind: SyncPendingOperationKind) async throws -> [PendingSyncOperationSnapshot] {
            try await pending.inFlightOperations(ownerUserID: me, kind: kind)
        }

        func isSettled() async throws -> Bool {
            var waiting = 0
            for kind in MemoryPendingOperationRefresh.memoryWriteKinds {
                waiting += try await queued(kind).count
            }
            return waiting == 0
        }

        func drain(context: SyncContext? = nil) async throws {
            let stream = PendingSyncOperationDrainStream(handlers: [
                createHandler,
                UpdateMemoryPendingOperationHandler(gateway: server, memoryStore: store),
                SetMemoryPlacePendingOperationHandler(gateway: server, memoryStore: store),
                HideMemoryPendingOperationHandler(gateway: server, memoryStore: store),
                UpsertMemoryNotePendingOperationHandler(gateway: server, memoryStore: store),
                DeleteMemoryNotePendingOperationHandler(gateway: server, memoryStore: store),
                AttachMemoryMediaPendingOperationHandler(gateway: server, memoryStore: store),
                RemoveMemoryMediaPendingOperationHandler(gateway: server, memoryStore: store),
            ])
            for _ in 0..<5 {
                if try await isSettled() { return }
                try await stream.push(context: context ?? self.context)
            }
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64 = 0

        func next() -> Int64 {
            lock.withLock {
                value += 1
                return value
            }
        }
    }
}
