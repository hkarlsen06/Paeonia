import Foundation
@testable import PaeoniaApp

actor VisitJoinServer: MemoryGateway {
    struct Photo: Equatable {
        let linkID: UUID
        let assetID: UUID
        let owner: UUID
        var text: String?
        var isRemoved = false
    }

    let me: UUID
    let partner: UUID
    let coupleID: UUID
    let joinedID: UUID
    let visitID: UUID
    private(set) var title = "Trip"
    private(set) var date = "2026-07-01"
    private(set) var place: MemoryPlace? = MemoryVisitJoinTests.place("Fløyen")
    private(set) var revision = 1
    private(set) var isDeleted = false
    private(set) var notes: [UUID: (body: String, revision: Int)] = [:]
    private(set) var photos: [Photo] = []
    private(set) var placeWrites = 0
    private(set) var attachedAssetIDs: [UUID] = []
    private var joinedCreates: Set<UUID> = []
    private var updatedAt = Date(timeIntervalSince1970: 100)
    private var onNextLoad: (@Sendable () async throws -> Void)?
    /// Refuses every attach the way the server refuses a sixth photo of one person.
    private var refusesAttach = false

    private static let notWritable = PaeoniaConvexError.server(code: "42501", message: "memory is not writable")
    private static let conflict = PaeoniaConvexError.server(code: "40001", message: "memory revision conflict")

    init(me: UUID, partner: UUID, coupleID: UUID, joinedID: UUID, visitID: UUID) {
        self.me = me
        self.partner = partner
        self.coupleID = coupleID
        self.joinedID = joinedID
        self.visitID = visitID
    }

    func seedPartner(photo: UUID) {
        notes[partner] = ("Partner's note", 1)
        photos.append(Photo(linkID: photo, assetID: photo, owner: partner))
    }

    /// Runs `hook` inside the next read of the memories, before the read answers.
    func runDuringNextLoad(_ hook: @escaping @Sendable () async throws -> Void) {
        onNextLoad = hook
    }

    func refuseAttach() {
        refusesAttach = true
    }

    func visiblePhotos(of owner: UUID) -> [UUID] {
        photos.filter { $0.owner == owner && !$0.isRemoved }.map(\.assetID)
    }

    func createMemory(_ payload: CreateMemoryOperationPayload, operation: SyncClientOperation) -> UUID {
        guard joinedCreates.insert(operation.id).inserted else { return joinedID }
        let note = [payload.title == title ? nil : payload.title, payload.noteBody].compactMap(\.self)
        if !note.isEmpty { notes[me] = (note.joined(separator: "\n\n"), 1) }
        photos += payload.optimisticMedia.map {
            Photo(linkID: $0.memoryMediaID, assetID: $0.mediaAssetID, owner: me, text: $0.accessibilityText)
        }
        if place == nil { place = payload.place }
        touch()
        return joinedID
    }

    func updateMemory(
        _ payload: UpdateMemoryOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        try requireJoined(payload.memoryID)
        guard payload.expectedRevision == revision else { throw Self.conflict }
        for description in payload.photoDescriptions {
            guard let index = photos.firstIndex(where: { $0.assetID == description.mediaAssetID }),
                  photos[index].owner == me, !photos[index].isRemoved else { throw Self.notWritable }
            photos[index].text = description.text
        }
        title = payload.title
        date = payload.memoryDate
        revision += 1
        touch()
        return nil
    }

    func setMemoryPlace(
        _ payload: SetMemoryPlaceOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        try requireJoined(payload.memoryID)
        place = payload.place
        placeWrites += 1
        touch()
        return nil
    }

    func hideMemory(
        _ payload: HideMemoryOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryRevisionResponse? {
        try requireJoined(payload.memoryID)
        guard payload.expectedRevision == revision else { throw Self.conflict }
        isDeleted = true
        touch()
        return nil
    }

    func upsertMemoryNote(
        _ payload: UpsertMemoryNoteOperationPayload,
        operation: SyncClientOperation
    ) throws -> MemoryNoteRevisionResponse? {
        try requireJoined(payload.memoryID)
        let current = notes[me]?.revision ?? 0
        guard (payload.expectedRevision ?? 0) == current else { throw Self.conflict }
        notes[me] = (payload.body, current + 1)
        touch()
        return nil
    }

    func deleteMemoryNote(_ payload: DeleteMemoryNoteOperationPayload, operation: SyncClientOperation) throws {
        try requireJoined(payload.memoryID)
        guard let note = notes[me] else { return }
        guard note.revision == payload.expectedRevision else { throw Self.conflict }
        notes[me] = nil
        touch()
    }

    func attachMemoryMedia(
        _ payload: AttachMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) throws -> [UUID] {
        try requireJoined(payload.memoryID)
        if refusesAttach {
            throw PaeoniaConvexError.server(code: "23514", message: "each partner can add at most 5 photos to a memory")
        }
        attachedAssetIDs += payload.mediaAssetIDs
        photos += payload.optimisticMedia.map {
            Photo(linkID: $0.memoryMediaID, assetID: $0.mediaAssetID, owner: me, text: $0.accessibilityText)
        }
        touch()
        return payload.optimisticMedia.map(\.memoryMediaID)
    }

    func removeMemoryMedia(
        _ payload: RemoveMemoryMediaOperationPayload,
        operation: SyncClientOperation
    ) throws -> UUID {
        guard let index = photos.firstIndex(where: { $0.linkID == payload.memoryMediaID }),
              photos[index].owner == me, !photos[index].isRemoved, !isDeleted else { throw Self.notWritable }
        photos[index].isRemoved = true
        touch()
        return payload.memoryMediaID
    }

    func loadMemories(updatedAfter: Date?, cursorMemoryID: UUID?, limit: Int) async throws -> [MemoryRemoteRow] {
        if let hook = onNextLoad {
            onNextLoad = nil
            try await hook()
        }
        return updatedAfter == nil ? [row] : []
    }

    private func requireJoined(_ memoryID: UUID) throws {
        guard memoryID == joinedID, !isDeleted else { throw Self.notWritable }
    }

    private func touch() {
        updatedAt = updatedAt.addingTimeInterval(1)
    }

    private var row: MemoryRemoteRow {
        let states = photos.enumerated().map { index, photo in
            MemoryMediaStateRow(
                memoryMediaID: photo.linkID, mediaAssetID: photo.assetID, ownerUserID: photo.owner,
                sortOrder: index + 1, deletedAt: photo.isRemoved ? updatedAt : nil, moderationStatus: .visible,
                assetDeletedAt: photo.isRemoved ? updatedAt : nil, assetModerationStatus: .visible,
                assetStorageDeleteStatus: photo.isRemoved ? "pending" : "none", accessibilityText: photo.text,
                updatedAt: updatedAt
            )
        }
        let visible = photos.filter { !$0.isRemoved }
        return MemoryRemoteRow(
            memoryID: joinedID, coupleID: coupleID, title: title, memoryDate: date, place: place,
            createdByUserID: partner, lastEditedByUserID: partner, revision: revision, moderationStatus: .visible,
            deletedAt: isDeleted ? updatedAt : nil, createdAt: Date(timeIntervalSince1970: 50), updatedAt: updatedAt,
            syncUpdatedAt: updatedAt,
            ownNoteID: notes[me].map { _ in UUID() }, ownNoteBody: notes[me]?.body,
            ownNoteRevision: notes[me]?.revision,
            ownNoteUpdatedAt: notes[me].map { _ in updatedAt }, ownNoteDeletedAt: nil,
            ownNoteModerationStatus: notes[me].map { _ in .visible },
            partnerNoteID: UUID(), partnerNoteUserID: partner, partnerNoteBody: notes[partner]?.body,
            partnerNoteRevision: notes[partner]?.revision, partnerNoteUpdatedAt: updatedAt, partnerNoteDeletedAt: nil,
            partnerNoteModerationStatus: .visible,
            memoryMediaIDs: visible.map(\.linkID), mediaAssetIDs: visible.map(\.assetID), memoryMediaStates: states,
            threadID: nil, visitID: visitID
        )
    }
}

/// Runs a hook the first time a write is marked failed, which the join does while it holds the
/// waiting memory. A hook that throws simulates the app quitting at that point.
actor HookedPendingStore: PendingSyncOperationPersisting {
    struct Crash: Error {}

    private let inner: InMemoryPendingSyncOperationRepository
    private var hook: (@Sendable () async throws -> Void)?

    init(
        _ inner: InMemoryPendingSyncOperationRepository,
        onFirstFailure hook: @escaping @Sendable () async throws -> Void
    ) {
        self.inner = inner
        self.hook = hook
    }

    func markTerminalFailure(clientOperationID: UUID, errorDescription: String, at date: Date) async throws {
        if let hook {
            self.hook = nil
            try await hook()
        }
        try await inner.markTerminalFailure(
            clientOperationID: clientOperationID, errorDescription: errorDescription, at: date
        )
    }

    func enqueue(_ request: PendingSyncOperationRequest) async throws {
        try await inner.enqueue(request)
    }

    func readyOperations(ownerUserID: UUID, limit: Int, now: Date) async throws -> [PendingSyncOperationSnapshot] {
        try await inner.readyOperations(ownerUserID: ownerUserID, limit: limit, now: now)
    }

    func nextPendingOperationDate(ownerUserID: UUID, now: Date) async throws -> Date? {
        try await inner.nextPendingOperationDate(ownerUserID: ownerUserID, now: now)
    }

    func inFlightOperations(ownerUserID: UUID, kind: SyncPendingOperationKind) async throws
        -> [PendingSyncOperationSnapshot] {
        try await inner.inFlightOperations(ownerUserID: ownerUserID, kind: kind)
    }

    func markSending(clientOperationID: UUID, at date: Date) async throws {
        try await inner.markSending(clientOperationID: clientOperationID, at: date)
    }

    func markSucceeded(clientOperationID: UUID, at date: Date) async throws {
        try await inner.markSucceeded(clientOperationID: clientOperationID, at: date)
    }

    func markRetryableFailure(
        clientOperationID: UUID,
        failure: PendingSyncFailure,
        nextRetryAt: Date?,
        at date: Date
    ) async throws {
        try await inner.markRetryableFailure(
            clientOperationID: clientOperationID, failure: failure, nextRetryAt: nextRetryAt, at: date
        )
    }

    func deleteCompleted(ownerUserID: UUID) async throws {
        try await inner.deleteCompleted(ownerUserID: ownerUserID)
    }

    func resetInFlight(ownerUserID: UUID) async throws {
        try await inner.resetInFlight(ownerUserID: ownerUserID)
    }
}

/// An edit started from inside the join, awaited after it.
actor LateEdit {
    private var task: Task<Void, any Error>?

    func start(_ work: @escaping @Sendable () async throws -> Void) {
        task = Task { try await work() }
    }

    func finish() async throws {
        try await task?.value
    }
}
