import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct GuessMySpotDraftPersistenceTests {
    @Test func reopeningRestoresThePhotoSceneAndPinAndQueuesTheSameDescription() async throws {
        let fixture = try DraftFixture()
        defer { fixture.removeFiles() }
        let first = await fixture.model()
        await first.reload()
        await first.pick(try fixture.imageData(.red))
        first.movePin(to: fixture.spot)
        first.updatePhotoDescription("A red house beside water.")
        let original = try #require(first.draft)
        let reopened = FileGuessMySpotPhotoStore(directoryURL: fixture.photoDirectory)
        let second = await fixture.model(photos: reopened)
        await second.reload()
        #expect(second.draft?.accessibilityText == original.accessibilityText)
        #expect(second.draft?.photo.jpeg == original.photo.jpeg)
        #expect(second.draft?.spot == fixture.spot)
        #expect(try reopened.draft(ownerUserID: UUID(), coupleID: fixture.couple) == nil)
        #expect(try reopened.draft(ownerUserID: fixture.owner, coupleID: UUID()) == nil)
        try #require(second.send())
        await second.moveTask?.value
        let queued = try await fixture.pending.inFlightOperations(ownerUserID: fixture.owner, kind: .guessMySpotSend)
        let data = try #require(queued.first?.requestData)
        let send = try JSONDecoder().decode(GuessMySpotSendPayload.self, from: data)
        #expect(send.details.accessibilityText == original.accessibilityText)
        #expect(send.details.spot == fixture.spot)
        #expect(try reopened.draft(ownerUserID: fixture.owner, coupleID: fixture.couple) == nil)
        #expect(reopened.photo(ownerUserID: fixture.owner, roundID: original.roundID) == original.photo.jpeg)
    }

    @Test func aDelayedRestoreCannotReplaceANewerPickOrDiscardIt() async throws {
        let fixture = try DraftFixture()
        defer { fixture.removeFiles() }
        let old = try fixture.seedDraft()
        let decoder = HeldGuessMySpotDraftDecoder()
        let model = await fixture.model(decode: { await decoder.decode($0) })
        let restore = Task { await model.reload() }
        defer { Task { await decoder.release() } }
        try #require(await decoder.waitForRequest())
        await model.pick(try fixture.imageData(.blue))
        model.updatePhotoDescription("The newer blue scene.")
        let newer = try #require(model.draft)
        await decoder.release()
        await restore.value
        #expect(model.draft?.roundID == newer.roundID)
        #expect(model.draft?.accessibilityText == newer.accessibilityText)
        try fixture.photos.discardDraft(roundID: old.roundID, ownerUserID: fixture.owner,
                                         coupleID: fixture.couple, keepingPhoto: false)
        let kept = try fixture.photos.draft(ownerUserID: fixture.owner, coupleID: fixture.couple)
        #expect(kept?.roundID == newer.roundID)
        model.clearDraft()
        #expect(try fixture.photos.draft(ownerUserID: fixture.owner, coupleID: fixture.couple) == nil)
        #expect(fixture.photos.photo(ownerUserID: fixture.owner, roundID: newer.roundID) == nil)
    }

    @Test func aPurgeWhileRestoringCannotRecreateThePhotoOrDescription() async throws {
        let fixture = try DraftFixture()
        defer { fixture.removeFiles() }
        let stored = try fixture.seedDraft()
        let ticket = fixture.photos.draftTicket(ownerUserID: fixture.owner)
        let decoder = HeldGuessMySpotDraftDecoder()
        let model = await fixture.model(decode: { await decoder.decode($0) })
        let restore = Task { await model.reload() }
        defer { Task { await decoder.release() } }
        try #require(await decoder.waitForRequest())
        #expect(await fixture.purger().purge(ownerUserID: fixture.owner, scope: .departingUser) == .completed)
        await decoder.release()
        await restore.value
        #expect(model.draft == nil)
        #expect(try fixture.photos.draft(ownerUserID: fixture.owner, coupleID: fixture.couple) == nil)
        #expect(fixture.photos.photo(ownerUserID: fixture.owner, roundID: stored.roundID) == nil)
        #expect((try? fixture.photos.saveDraft(stored, ownerUserID: fixture.owner,
                                               coupleID: fixture.couple, ticket: ticket)) != true)
    }

    @Test func aNewRelationshipCannotRestoreThePrecedingCouplesDraft() async throws {
        let fixture = try DraftFixture()
        defer { fixture.removeFiles() }
        _ = try fixture.seedDraft()
        let model = await fixture.model()
        await model.reload()
        try #require(model.draft != nil)
        let nextCouple = UUID()
        model.configure(participants: GameParticipants(currentUserID: fixture.owner, coupleID: nextCouple,
                                                        partnerName: "Another partner", currentName: "Alex"))
        await model.reload()
        #expect(model.draft == nil)
        #expect(model.state == nil)
        #expect(try fixture.photos.draft(ownerUserID: fixture.owner, coupleID: nextCouple) == nil)
    }

    @Test func temporaryAccessHideKeepsAQueuedPhotoReadableAfterAccessReturns() async throws {
        let fixture = try DraftFixture()
        defer { fixture.removeFiles() }
        let model = await fixture.model()
        await model.reload()
        await model.pick(try fixture.imageData(.red))
        model.movePin(to: fixture.spot)
        model.updatePhotoDescription("The scene kept during a temporary access change.")
        let original = try #require(model.draft)
        try #require(model.send())
        await model.moveTask?.value
        #expect(await fixture.purger().purge(ownerUserID: fixture.owner,
                                              scope: .relationshipAccessHidden) == .completed)
        let resumed = await fixture.model(photos: FileGuessMySpotPhotoStore(directoryURL: fixture.photoDirectory))
        await resumed.reload()
        let round = try #require(resumed.round)
        #expect(resumed.phase == .waitingForGuess(isQueued: true))
        #expect(round.photoAccessibilityText == original.accessibilityText)
        #expect(await resumed.photo(of: round) != nil)
        #expect(resumed.draft == nil)
    }

    @Test func anOwnerCorrectionPersistsWithoutChangingThePhotoOrPrivateSpot() async throws {
        let fixture = try DraftFixture()
        defer { fixture.removeFiles() }
        let round = RemoteGuessMySpotRound(
            id: UUID(), roundNumber: 1, senderUserID: fixture.owner, guesserUserID: fixture.partner,
            photoMediaAssetID: UUID(), photoWidth: 80, photoHeight: 60,
            spotLatitude: fixture.spot.latitude, spotLongitude: fixture.spot.longitude,
            placeName: "Private place", takenOn: "2024-01-01", sentAt: GameFixture.now,
            photoAccessibilityText: "Earlier scene."
        )
        await fixture.cache.saveState(fixture.state(round: round), ownerUserID: fixture.owner)
        let updater = MediaAlternativeCacheUpdater(
            chat: FileThreadChatCache(directoryURL: fixture.directory.appendingPathComponent("chat")),
            stories: FileStoriesCache(directoryURL: fixture.directory.appendingPathComponent("stories")),
            daily: FileDailyChallengeSnapshotCache(directoryURL: fixture.directory.appendingPathComponent("daily")),
            guessMySpot: fixture.cache
        )
        let service = MediaAlternativeEditingService(pending: fixture.pending, cache: updater)
        let edit = MediaAlternativeEdit(coupleID: fixture.couple, target: .guessMySpot(roundID: round.id),
                                        text: "The corrected scene.")
        try await service.queue(
            edit, ownerUserID: fixture.owner, operation: fixture.environment.operations.makeOperation(),
            stamp: await updater.stamp(ownerUserID: fixture.owner)
        )
        let reopened = FileGuessMySpotCache(directoryURL: fixture.cacheDirectory)
        let corrected = await reopened.document(ownerUserID: fixture.owner).state?.currentRound
        #expect(corrected?.photoAccessibilityText == edit.text)
        #expect(corrected?.spot == round.spot)
        #expect(corrected?.photoMediaAssetID == round.photoMediaAssetID)
        #expect(corrected?.sentAt == round.sentAt)
    }
}

@MainActor
private final class DraftFixture {
    let owner = UUID(), partner = UUID(), couple = UUID()
    let gameID = UUID()
    let spot = GuessMySpotCoordinate(latitude: 60.39, longitude: 5.32)
    let directory: URL
    let environment = GamesTestEnvironment(state: nil)
    let localStore: PaeoniaLocalStore
    let photos: FileGuessMySpotPhotoStore
    let cache: FileGuessMySpotCache
    var models: [GuessMySpotViewModel] = []

    var photoDirectory: URL { directory.appendingPathComponent("photos") }
    var cacheDirectory: URL { directory.appendingPathComponent("cache") }
    var pending: SwiftDataPendingSyncOperationRepository {
        SwiftDataPendingSyncOperationRepository(container: localStore.container)
    }

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.directory = directory
        localStore = try PaeoniaLocalStore(inMemory: true)
        photos = FileGuessMySpotPhotoStore(directoryURL: directory.appendingPathComponent("photos"))
        cache = FileGuessMySpotCache(directoryURL: directory.appendingPathComponent("cache"))
    }

    func state(round: RemoteGuessMySpotRound? = nil) -> RemoteGuessMySpotState {
        RemoteGuessMySpotState(
            userID: owner, partnerUserID: partner, coupleID: couple, dataEpoch: "",
            game: RemoteGuessMySpotGame(
                id: gameID, turnUserID: round?.guesserUserID ?? owner, turnStartedAt: GameFixture.now,
                sharedPoints: 0, myPoints: 0, partnerPoints: 0, roundCount: round?.roundNumber ?? 0,
                version: 1, createdByUserID: owner, createdAt: GameFixture.now, updatedAt: GameFixture.now
            ),
            currentRound: round, previousRound: nil
        )
    }

    func model(photos: (any GuessMySpotPhotoStoring)? = nil,
               decode: (@Sendable (Data) async -> UIImage?)? = nil) async -> GuessMySpotViewModel {
        if await cache.document(ownerUserID: owner).state == nil { await cache.saveState(state(), ownerUserID: owner) }
        var dependencies = environment.dependencies()
        dependencies.guessMySpotCache = cache
        dependencies.guessMySpotPhotos = photos ?? self.photos
        dependencies.pendingOperationStore = pending
        let model = GuessMySpotViewModel(
            dependencies: dependencies,
            participants: GameParticipants(currentUserID: owner, coupleID: couple,
                                            partnerName: "Robin", currentName: "Alex"),
            decodeDraftPhoto: decode ?? { UIImage(data: $0) }
        )
        models.append(model)
        return model
    }

    func imageData(_ color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        return try #require(image.pngData())
    }

    func seedDraft() throws -> GuessMySpotStoredDraft {
        let bytes = try imageData(.red)
        let prepared = try #require(GuessMySpotPhotoReader.prepare(bytes))
        let draft = GuessMySpotStoredDraft(roundID: UUID(), photo: prepared, spot: spot,
                                           place: nil, refusedRoundID: nil, accessibilityText: "The older red scene.")
        try #require(try photos.saveDraft(draft, ownerUserID: owner, coupleID: couple,
                                       ticket: photos.draftTicket(ownerUserID: owner)))
        return draft
    }

    func purger() -> LocalPrivacyPurgeService {
        let widgets = WidgetCanvasTestEnvironment()
        return LocalPrivacyPurgeService(
            recordStore: SwiftDataLocalPrivacyRecordStore(container: localStore.container),
            privateContentPurger: LiveLocalPrivateContentPurger(
                widgetSync: NoOpWidgetCanvasSync(), widgetCanvas: widgets.makeService(), partnerAvatar: nil,
                dailyAnswerMediaCache: nil, memoryMediaCache: nil, profilePhotoCache: nil,
                guessMySpotCache: cache, guessMySpotPhotos: photos
            ),
            retryStore: InMemoryLocalPrivacyPurgeRetryStore(), automaticallyRetry: false
        )
    }

    func removeFiles() {
        for model in models { model.namingTask?.cancel(); model.photoTask?.cancel() }
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor HeldGuessMySpotDraftDecoder {
    private var requests = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func decode(_ data: Data) async -> UIImage? {
        requests += 1
        if requests == 1 { await withCheckedContinuation { continuation = $0 } }
        return UIImage(data: data)
    }

    func waitForRequest() async -> Bool {
        for _ in 0..<300 {
            if requests > 0 { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func release() { continuation?.resume(); continuation = nil }
}
