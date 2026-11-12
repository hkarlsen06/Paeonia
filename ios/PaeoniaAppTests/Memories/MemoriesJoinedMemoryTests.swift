import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

/// Actions the person started on their visit memory that finish after it joined the partner's
/// memory for the visit, when this phone's copy is gone and the screen shows the joined memory.
@MainActor
struct MemoriesJoinedMemoryTests {
    @Test func aDeleteConfirmedAfterTheMemoryJoinedTakesOnlyTheirPartOff() async throws {
        let env = try await joinedEnvironment()

        await env.viewModel.deleteMemory(env.waiting)

        let removed = try await env.queued(.removeMemoryMedia, as: RemoveMemoryMediaOperationPayload.self)
        let notes = try await env.queued(.deleteMemoryNote, as: DeleteMemoryNoteOperationPayload.self)
        #expect(try await env.queued(.hideMemory, as: HideMemoryOperationPayload.self).isEmpty)
        #expect(removed.map(\.memoryMediaID) == [env.theirPhoto])
        #expect(notes.map(\.memoryID) == [env.joinedID])
        #expect(env.viewModel.notice == .ownPartRemovedAfterJoin)
    }

    @Test func aPlacePickedAfterTheMemoryJoinedSaysWhyItWasNotAdded() async throws {
        let env = try await joinedEnvironment()

        let saved = await env.viewModel.setPlace(
            MemoryPlace(name: "Bryggen", latitude: 60.39, longitude: 5.32, city: "Bergen", countryCode: "NO"),
            forMemory: env.waiting.snapshot.memoryID
        )

        #expect(!saved)
        #expect(env.viewModel.notice == .placeNotAddedAfterJoin)
        #expect(try await env.queued(.setMemoryPlace, as: SetMemoryPlaceOperationPayload.self).isEmpty)
    }

    // MARK: - Environment

    struct Environment {
        let viewModel: MemoriesViewModel
        let pending: InMemoryPendingSyncOperationRepository
        let userID: UUID
        let waiting: MemoryRecord
        let joinedID: UUID
        /// The person's photo from the waiting memory, which the join moved.
        let theirPhoto: UUID

        func queued<Payload: Decodable>(_ kind: SyncPendingOperationKind, as _: Payload.Type) async throws
            -> [Payload] {
            try await pending.inFlightOperations(ownerUserID: userID, kind: kind).map {
                try JSONDecoder().decode(Payload.self, from: $0.requestData ?? Data())
            }
        }
    }

    /// A visit memory with one photo saved on this phone, then the end of its join: the partner's
    /// memory holds that photo, the person's note, another photo of theirs added earlier and the
    /// partner's photo, and this phone's copy is gone.
    private func joinedEnvironment() async throws -> Environment {
        let store = InMemoryMemoryRecordRepository()
        let pending = InMemoryPendingSyncOperationRepository()
        let viewModel = MemoriesViewModel(
            memoryService: MemoryDataService(memoryStore: store, pendingOperationStore: pending),
            operationProvider: MemoryTestOperationProvider(), mediaUploader: MemoryTestMediaUploader(),
            mediaImageCache: nil, draftStore: makeIsolatedMemoryDraftStore()
        )
        let (userID, partnerID, coupleID, visitID, joinedID) = (UUID(), UUID(), UUID(), UUID(), UUID())
        await viewModel.configure(currentUserID: userID, coupleID: coupleID)
        let created = await viewModel.createMemory(
            title: "Bergen", date: "2026-06-30", note: "Rain", photos: [makeMemoryTestImageData(color: .systemPink)],
            visitID: visitID
        )
        #expect(created)
        let waiting = try #require(viewModel.timeline.flatMap(\.memories).first)
        let theirPhoto = try #require(waiting.snapshot.media.first).memoryMediaID
        let photos: [(id: UUID, owner: UUID)] = [(theirPhoto, userID), (UUID(), userID), (UUID(), partnerID)]
        try await store.saveRemote(
            [Self.joinedRow(joinedID, coupleID: coupleID, by: partnerID, visitID: visitID, photos: photos)],
            ownerUserID: userID, mergePolicy: .preserveLocalChanges
        )
        await viewModel.load()
        await store.remove(ownerUserID: userID, memoryID: waiting.snapshot.memoryID)
        await viewModel.load()
        return Environment(
            viewModel: viewModel, pending: pending, userID: userID, waiting: waiting, joinedID: joinedID,
            theirPhoto: theirPhoto
        )
    }

    private static func joinedRow(
        _ memoryID: UUID,
        coupleID: UUID,
        by partner: UUID,
        visitID: UUID,
        photos: [(id: UUID, owner: UUID)]
    ) -> MemoryRemoteRow {
        let at = Date(timeIntervalSince1970: 50)
        let states = photos.enumerated().map { index, photo in
            MemoryMediaStateRow(
                memoryMediaID: photo.id, mediaAssetID: photo.id, ownerUserID: photo.owner, sortOrder: index + 1,
                deletedAt: nil, moderationStatus: .visible, assetDeletedAt: nil, assetModerationStatus: .visible,
                assetStorageDeleteStatus: "none", accessibilityText: nil, updatedAt: at
            )
        }
        return MemoryRemoteRow(
            memoryID: memoryID, coupleID: coupleID, title: "Trip", memoryDate: "2026-07-01", place: nil,
            createdByUserID: partner, lastEditedByUserID: partner, revision: 1, moderationStatus: .visible,
            deletedAt: nil, createdAt: at, updatedAt: at, syncUpdatedAt: at,
            ownNoteID: UUID(), ownNoteBody: "Bergen\n\nRain", ownNoteRevision: 1, ownNoteUpdatedAt: at,
            ownNoteDeletedAt: nil, ownNoteModerationStatus: .visible,
            partnerNoteID: UUID(), partnerNoteUserID: partner, partnerNoteBody: "Partner's note",
            partnerNoteRevision: 1, partnerNoteUpdatedAt: at, partnerNoteDeletedAt: nil,
            partnerNoteModerationStatus: .visible,
            memoryMediaIDs: photos.map(\.id), mediaAssetIDs: photos.map(\.id), memoryMediaStates: states,
            threadID: nil, visitID: visitID
        )
    }
}
