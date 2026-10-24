import Foundation
import PencilKit
import SwiftData
import Testing
import UIKit
@testable import PaeoniaApp

struct LocalPrivacyPurgeTests {
    @Test func departingUserPurgeDeletesOnlyTheDepartingOwnersRecords() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let departingUserID = UUID()
        let remainingUserID = UUID()
        let context = ModelContext(store.container)
        try seedAllRecords(ownerUserID: departingUserID, in: context)
        try seedAllRecords(ownerUserID: remainingUserID, in: context)

        let purger = SwiftDataLocalPrivacyRecordStore(container: store.container)
        try await purger.purgeDepartingUser(ownerUserID: departingUserID)
        try await purger.purgeDepartingUser(ownerUserID: departingUserID)

        #expect(try counts(ownerUserID: departingUserID, container: store.container) == .empty)
        #expect(
            try counts(ownerUserID: remainingUserID, container: store.container)
                == .fullySeeded
        )
    }

    @Test(.timeLimit(.minutes(1))) func relationshipPurgeTellsOpenScreensTheirRowsAreGone() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let ownerUserID = UUID()
        try seedAllRecords(ownerUserID: ownerUserID, in: ModelContext(store.container))
        let changes = LocalStoreChanges.changes(in: .memories, .locationVisibility)

        try await SwiftDataLocalPrivacyRecordStore(container: store.container)
            .purgeRelationshipContent(ownerUserID: ownerUserID, clearAccessSnapshot: false)

        var iterator = changes.filter { $0.ownerUserID == ownerUserID }.makeAsyncIterator()
        let first = await iterator.next()?.domain
        let second = await iterator.next()?.domain
        #expect(Set([first, second]) == [.memories, .locationVisibility])
    }

    /// The hide keeps a queued sharing change, so it must keep the unconfirmed
    /// choice too. Dropping it let the server's older value show sharing as on.
    @Test func temporaryHideKeepsAnUnconfirmedSharingChoiceButPermanentLossDropsIt() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let ownerUserID = UUID()
        let key = LocalLocationVisibilitySnapshot.storageKey(ownerUserID: ownerUserID, coupleID: UUID())
        let ledger = PendingSharingChoiceLedger.shared
        ledger.withChoices { $0[key] = false }
        defer { ledger.removeChoices(ownerUserID: ownerUserID) }
        let purger = SwiftDataLocalPrivacyRecordStore(container: store.container)

        try await purger.hideRelationshipAccess(ownerUserID: ownerUserID)
        #expect(ledger.withChoices { $0[key] } == false)

        try await purger.purgeRelationshipContent(ownerUserID: ownerUserID, clearAccessSnapshot: false)
        #expect(ledger.withChoices { $0[key] } == nil)
    }

    @Test func temporaryHidePreservesOwnedContentButPermanentLossPurgesIt() async throws {
        let store = try PaeoniaLocalStore(inMemory: true)
        let ownerUserID = UUID()
        let context = ModelContext(store.container)
        try seedAllRecords(ownerUserID: ownerUserID, in: context)
        let purger = SwiftDataLocalPrivacyRecordStore(container: store.container)

        try await purger.hideRelationshipAccess(ownerUserID: ownerUserID)
        try await purger.hideRelationshipAccess(ownerUserID: ownerUserID)

        #expect(
            try counts(ownerUserID: ownerUserID, container: store.container)
                == .afterHide
        )

        try await purger.purgeRelationshipContent(
            ownerUserID: ownerUserID,
            clearAccessSnapshot: false
        )
        try await purger.purgeRelationshipContent(
            ownerUserID: ownerUserID,
            clearAccessSnapshot: false
        )

        #expect(
            try counts(ownerUserID: ownerUserID, container: store.container)
                == .afterContentPurge
        )

        try await purger.purgeRelationshipContent(
            ownerUserID: ownerUserID,
            clearAccessSnapshot: true
        )

        #expect(
            try counts(ownerUserID: ownerUserID, container: store.container)
                == .afterFullPurge
        )
    }

    @Test func recordDeletionFailureIsDurableAndPrivateFilesStillPurge() async throws {
        let ownerUserID = UUID()
        let filePurger = RecordingPrivateContentPurger()
        let recordStore = ScriptedLocalPrivacyRecordStore(failuresBeforeSuccess: 1)
        let retryStore = InMemoryLocalPrivacyPurgeRetryStore()
        let purger = LocalPrivacyPurgeService(
            recordStore: recordStore,
            privateContentPurger: filePurger,
            retryStore: retryStore,
            automaticallyRetry: false
        )

        let firstResult = await purger.purge(
            ownerUserID: ownerUserID,
            scope: .departingUser
        )

        #expect(firstResult == .recordsPendingRetry)
        #expect(
            await retryStore.request(for: ownerUserID)
                == LocalPrivacyPurgeRequest(ownerUserID: ownerUserID, scope: .departingUser)
        )

        #expect(
            await filePurger.calls == [
                PrivacyFilePurgeCall(ownerUserID: ownerUserID, scope: .departingUser)
            ]
        )

        let retryResult = await purger.retryPendingPurges()

        #expect(retryResult == .completed)
        #expect(await retryStore.request(for: ownerUserID) == nil)
        #expect(await recordStore.calls == [.departingUser, .departingUser])
        // Record retries must not repeat already-completed file/App Group cleanup.
        #expect(await filePurger.calls.count == 1)
    }

    @Test func pendingBroaderPurgeCannotBeReplacedByLaterNarrowerScope() async throws {
        let ownerUserID = UUID()
        let recordStore = ScriptedLocalPrivacyRecordStore(failuresBeforeSuccess: 2)
        let retryStore = InMemoryLocalPrivacyPurgeRetryStore()
        let purger = LocalPrivacyPurgeService(
            recordStore: recordStore,
            privateContentPurger: RecordingPrivateContentPurger(),
            retryStore: retryStore,
            automaticallyRetry: false
        )

        #expect(
            await purger.purge(ownerUserID: ownerUserID, scope: .departingUser)
                == .recordsPendingRetry
        )
        #expect(
            await purger.purge(ownerUserID: ownerUserID, scope: .relationshipAccessHidden)
                == .recordsPendingRetry
        )

        #expect(await purger.retryPendingPurges() == .completed)

        #expect(await retryStore.request(for: ownerUserID) == nil)
        #expect(
            await recordStore.calls == [
                .departingUser,
                .departingUser,
                .departingUser
            ]
        )
    }

    @Test func permanentPurgeMergesAccessSnapshotRequirement() async throws {
        let ownerUserID = UUID()
        let retryStore = InMemoryLocalPrivacyPurgeRetryStore()

        await retryStore.enqueue(
            LocalPrivacyPurgeRequest(
                ownerUserID: ownerUserID,
                scope: .relationshipContentPurged(clearAccessSnapshot: false)
            )
        )
        await retryStore.enqueue(
            LocalPrivacyPurgeRequest(
                ownerUserID: ownerUserID,
                scope: .relationshipContentPurged(clearAccessSnapshot: true)
            )
        )

        #expect(
            await retryStore.request(for: ownerUserID)
                == LocalPrivacyPurgeRequest(
                    ownerUserID: ownerUserID,
                    scope: .relationshipContentPurged(clearAccessSnapshot: true)
                )
        )
    }

    @Test func userDefaultsRetryLedgerSurvivesStoreRecreation() async throws {
        let suiteName = "LocalPrivacyPurgeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ownerUserID = UUID()
        let request = LocalPrivacyPurgeRequest(
            ownerUserID: ownerUserID,
            scope: .relationshipContentPurged(clearAccessSnapshot: true)
        )

        let firstStore = UserDefaultsLocalPrivacyPurgeRetryStore(defaults: defaults)
        try await firstStore.enqueue(request)

        let recreatedStore = UserDefaultsLocalPrivacyPurgeRetryStore(defaults: defaults)
        #expect(try await recreatedStore.request(for: ownerUserID) == request)

        try await recreatedStore.remove(request)
        #expect(try await recreatedStore.pendingRequests().isEmpty)
    }

    @Test func inMemoryRetrySurvivesLedgerWriteFailureForCurrentLaunch() async {
        let ownerUserID = UUID()
        let recordStore = ScriptedLocalPrivacyRecordStore(failuresBeforeSuccess: 1)
        let purger = LocalPrivacyPurgeService(
            recordStore: recordStore,
            privateContentPurger: RecordingPrivateContentPurger(),
            retryStore: FailingLocalPrivacyPurgeRetryStore(),
            automaticallyRetry: false
        )

        #expect(
            await purger.purge(ownerUserID: ownerUserID, scope: .departingUser)
                == .recordsFailedWithoutDurableRetry
        )
        #expect(await purger.retryPendingPurges() == .recordsPendingRetry)
        #expect(await recordStore.calls == [.departingUser, .departingUser])
    }

    /// Sign-out and account deletion purge as `.departingUser`. Losing the
    /// relationship purges with one of the other three scopes.
    static let everyPurgeScope: [LocalPrivacyPurgeScope] = [
        .departingUser,
        .relationshipContentPurged(clearAccessSnapshot: true),
        .relationshipContentPurged(clearAccessSnapshot: false),
        .relationshipAccessHidden,
    ]

    @Test(arguments: everyPurgeScope)
    func everyPurgeRemovesCachedMemoryPhotos(scope: LocalPrivacyPurgeScope) async throws {
        let memoryMediaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalPrivacyPurgeTests-\(UUID().uuidString)", isDirectory: true)
        let diskCache = MemoryMediaImageDiskCache(directoryURL: memoryMediaURL)
        let photoID = UUID()
        await diskCache.store(Data([0xFF, 0xD8, 0xFF]), for: photoID)
        let photoURL = await diskCache.fileURL(for: photoID)
        try #require(FileManager.default.fileExists(atPath: photoURL.path))
        let widgets = WidgetCanvasTestEnvironment()
        let fixture = try LivePurgeFixture(widgetCanvas: widgets.makeService(), memoryMediaURL: memoryMediaURL)

        #expect(await fixture.purger.purge(ownerUserID: UUID(), scope: scope) == .completed)

        #expect(!FileManager.default.fileExists(atPath: photoURL.path))
    }

    @Test(arguments: everyPurgeScope)
    func everyPurgeRemovesWhatTheLockScreenAndHomeScreenWidgetsShow(
        scope: LocalPrivacyPurgeScope
    ) async throws {
        let widgets = WidgetCanvasTestEnvironment()
        let widgetCanvas = widgets.makeService()
        try await widgetCanvas.saveDrawing(
            makeNonEmptyDrawing().dataRepresentation(),
            canvasSize: CGSize(width: 300, height: 300),
            authorName: "Hjalmar",
            createdAt: Date()
        )
        // The Lock Screen widgets and the Home Screen widgets other than the drawing read this file.
        let lockScreenURL = widgets.url(relativePath: LockScreenCache.relativePath)
        try Data(#"{"snapshot":"names, dates and countdown titles"}"#.utf8).write(to: lockScreenURL)
        try #require(FileManager.default.fileExists(atPath: widgets.payloadURL.path))
        try #require(!widgets.previewFiles.isEmpty)
        let fixture = try LivePurgeFixture(
            widgetCanvas: widgetCanvas,
            memoryMediaURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("LocalPrivacyPurgeTests-\(UUID().uuidString)", isDirectory: true)
        )
        let reloadsBeforePurge = widgets.reloader.reloadCount

        #expect(await fixture.purger.purge(ownerUserID: UUID(), scope: scope) == .completed)

        #expect(!FileManager.default.fileExists(atPath: lockScreenURL.path))
        #expect(!FileManager.default.fileExists(atPath: widgets.payloadURL.path))
        #expect(widgets.previewFiles.isEmpty)
        // Widgets keep showing their last timeline until they reload.
        #expect(widgets.reloader.reloadCount > reloadsBeforePurge)
    }
}

/// The real purge service and file purger, with the widget files and memory photos
/// in temporary directories. The other caches are the app's own, as at sign-out.
private struct LivePurgeFixture {
    let localStore: PaeoniaLocalStore
    let purger: LocalPrivacyPurgeService

    init(widgetCanvas: WidgetCanvasService, memoryMediaURL: URL) throws {
        let client = PaeoniaConvexClient(
            deploymentURL: try #require(URL(string: "https://privacy-purge.invalid")),
            session: URLSession(configuration: .ephemeral),
            tokenProvider: { nil }
        )
        localStore = try PaeoniaLocalStore(inMemory: true)
        purger = LocalPrivacyPurgeService(
            recordStore: SwiftDataLocalPrivacyRecordStore(container: localStore.container),
            privateContentPurger: LiveLocalPrivateContentPurger(
                widgetSync: NoOpWidgetCanvasSync(),
                widgetCanvas: widgetCanvas,
                partnerAvatar: nil,
                dailyAnswerMediaCache: nil,
                memoryMediaCache: MemoryMediaImageService(client: client, directoryURL: memoryMediaURL),
                profilePhotoCache: nil
            ),
            retryStore: InMemoryLocalPrivacyPurgeRetryStore(),
            automaticallyRetry: false
        )
    }
}

private enum LocalPrivacyTestError: Error {
    case simulatedFailure
}

private actor ScriptedLocalPrivacyRecordStore: LocalPrivacyRecordPurging {
    private(set) var calls: [LocalPrivacyPurgeScope] = []
    private var failuresRemaining: Int

    init(failuresBeforeSuccess: Int) {
        failuresRemaining = failuresBeforeSuccess
    }

    func purgeDepartingUser(ownerUserID _: UUID) throws {
        try record(.departingUser)
    }

    func hideRelationshipAccess(ownerUserID _: UUID) throws {
        try record(.relationshipAccessHidden)
    }

    func purgeRelationshipContent(
        ownerUserID _: UUID,
        clearAccessSnapshot: Bool
    ) throws {
        try record(.relationshipContentPurged(clearAccessSnapshot: clearAccessSnapshot))
    }

    private func record(_ scope: LocalPrivacyPurgeScope) throws {
        calls.append(scope)
        guard failuresRemaining > 0 else {
            return
        }
        failuresRemaining -= 1
        throw LocalPrivacyTestError.simulatedFailure
    }
}

private actor InMemoryLocalPrivacyPurgeRetryStore: LocalPrivacyPurgeRetryStoring {
    private var requests: [UUID: LocalPrivacyPurgeRequest] = [:]

    func enqueue(_ request: LocalPrivacyPurgeRequest) {
        if let existing = requests[request.ownerUserID] {
            requests[request.ownerUserID] = existing.merging(request)
        } else {
            requests[request.ownerUserID] = request
        }
    }

    func pendingRequests() -> [LocalPrivacyPurgeRequest] {
        Array(requests.values)
    }

    func request(for ownerUserID: UUID) -> LocalPrivacyPurgeRequest? {
        requests[ownerUserID]
    }

    func remove(_ completedRequest: LocalPrivacyPurgeRequest) {
        guard requests[completedRequest.ownerUserID] == completedRequest else {
            return
        }
        requests.removeValue(forKey: completedRequest.ownerUserID)
    }
}

private actor FailingLocalPrivacyPurgeRetryStore: LocalPrivacyPurgeRetryStoring {
    func enqueue(_ request: LocalPrivacyPurgeRequest) throws {
        throw LocalPrivacyTestError.simulatedFailure
    }

    func pendingRequests() throws -> [LocalPrivacyPurgeRequest] {
        throw LocalPrivacyTestError.simulatedFailure
    }

    func request(for ownerUserID: UUID) throws -> LocalPrivacyPurgeRequest? {
        throw LocalPrivacyTestError.simulatedFailure
    }

    func remove(_ completedRequest: LocalPrivacyPurgeRequest) throws {
        throw LocalPrivacyTestError.simulatedFailure
    }
}

private struct PrivacyFilePurgeCall: Equatable, Sendable {
    let ownerUserID: UUID
    let scope: LocalPrivacyPurgeScope
}

private actor RecordingPrivateContentPurger: LocalPrivateContentPurging {
    private(set) var calls: [PrivacyFilePurgeCall] = []

    func purge(ownerUserID: UUID, scope: LocalPrivacyPurgeScope) {
        calls.append(PrivacyFilePurgeCall(ownerUserID: ownerUserID, scope: scope))
    }
}
