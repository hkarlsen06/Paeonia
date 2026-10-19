import Foundation
import Testing
@testable import PaeoniaApp

struct FirstDayDrawingUploadServiceTests {
    private func makeService(
        gateway: FirstDayGatewaySpy,
        canvas: FirstDayCanvasFake = FirstDayCanvasFake(),
        defaults: UserDefaults
    ) -> (FirstDayDrawingUploadService, WidgetPendingUploadStore) {
        let pendingStore = WidgetPendingUploadStore(defaults: defaults, retryDelay: 0)
        let service = FirstDayDrawingUploadService(
            gateway: gateway,
            operationFactory: FirstDayOperationsFake(),
            pendingStore: pendingStore,
            localStore: canvas
        )
        return (service, pendingStore)
    }

    @Test func aSendGoesThroughTheDraftAndClearsTheNotSentMarker() async throws {
        let defaults = try firstDayTestDefaults()
        let gateway = FirstDayGatewaySpy()
        let (service, pendingStore) = makeService(gateway: gateway, defaults: defaults)
        let payload = firstDayPayload()

        _ = await service.markPending(payload)
        let delivery = await service.send(payload)

        #expect(delivery == .delivered)
        #expect(await gateway.steps == ["reserve", "upload", "finalize", "save"])
        #expect(!pendingStore.hasPending)
    }

    @Test func aFailedSendKeepsTheDrawingWaiting() async throws {
        let defaults = try firstDayTestDefaults()
        let gateway = FirstDayGatewaySpy()
        await gateway.fail("save")
        let (service, pendingStore) = makeService(gateway: gateway, defaults: defaults)
        let payload = firstDayPayload()

        _ = await service.markPending(payload)
        let delivery = await service.send(payload)

        #expect(delivery == .waiting)
        #expect(pendingStore.hasPending)
        // An ended relationship's purge keeps a first day drawing that has not gone out.
        #expect(pendingStore.pendingSnapshot?.isFirstDay == true)
        #expect(await service.hasPendingUpload)
    }

    @Test func aRetrySendsTheFirstDrawingSavedOnThisPhone() async throws {
        let defaults = try firstDayTestDefaults()
        let payload = firstDayPayload()
        let gateway = FirstDayGatewaySpy()
        await gateway.fail("upload")
        let (service, pendingStore) = makeService(
            gateway: gateway,
            canvas: FirstDayCanvasFake(drawingData: payload.drawingData),
            defaults: defaults
        )
        _ = await service.markPending(payload)
        #expect(await service.send(payload) == .waiting)

        await gateway.fail("none")
        let isSent = await service.retryPending()

        #expect(isSent)
        #expect(!pendingStore.hasPending)
        #expect(await gateway.steps.suffix(4) == ["reserve", "upload", "finalize", "save"])
    }

    @Test func aRetryLeavesAPairedDrawingToTheCouplesUploader() async throws {
        let defaults = try firstDayTestDefaults()
        let payload = firstDayPayload()
        let gateway = FirstDayGatewaySpy()
        let (service, pendingStore) = makeService(
            gateway: gateway,
            canvas: FirstDayCanvasFake(drawingData: payload.drawingData),
            defaults: defaults
        )
        pendingStore.markPending(payload, contentHash: FirstDayDrawingUploadService.sha256Hex(of: payload.drawingData))

        let isSent = await service.retryPending()

        #expect(!isSent)
        #expect(pendingStore.hasPending)
        #expect(await gateway.steps.isEmpty)
    }
}

@MainActor
struct InviterFirstDayModelTests {
    private func makeModel(
        gateway: FirstDayGatewaySpy,
        canvas: FirstDayCanvasFake = FirstDayCanvasFake(),
        push: FirstDayPushFake = FirstDayPushFake(),
        defaults: UserDefaults
    ) -> InviterFirstDayModel {
        InviterFirstDayModel(
            ownerUserID: firstDayUUID(100),
            authorName: "Alex",
            gateway: gateway,
            uploader: FirstDayDrawingUploadService(
                gateway: gateway,
                operationFactory: FirstDayOperationsFake(),
                pendingStore: WidgetPendingUploadStore(defaults: defaults),
                localStore: canvas
            ),
            canvas: canvas,
            downloader: FirstDayDownloaderFake(),
            pushAuthorization: push,
            rasterizer: FirstDayRasterizerFake(),
            identityStore: WidgetSyncIdentityStore(defaults: defaults),
            questionPreferences: FirstDayPreferencesFake()
        )
    }

    private let drawingReference = FirstDayDrawingReference(
        mediaAssetID: firstDayUUID(50),
        revisionID: firstDayUUID(51)
    )

    @Test func afterAReinstallTheThumbnailComesFromTheServerAndTheWidgetIsLeftAlone() async throws {
        let defaults = try firstDayTestDefaults()
        let gateway = FirstDayGatewaySpy(draft: firstDayDraft(answered: 0, drawing: drawingReference))
        let canvas = FirstDayCanvasFake()
        let model = makeModel(gateway: gateway, canvas: canvas, defaults: defaults)

        await model.load()

        #expect(model.drawingThumbnail != nil)
        #expect(await gateway.steps.contains("signedURL"))
        // The widget extension puts the server's copy on the widget.
        #expect(await canvas.drawingData == nil)
        #expect(!WidgetPendingUploadStore(defaults: defaults).hasPending)
    }

    @Test func loadSavesTheNameTheWidgetShowsForTheFirstDrawing() async throws {
        let defaults = try firstDayTestDefaults()
        let model = makeModel(gateway: FirstDayGatewaySpy(), defaults: defaults)

        await model.load()

        let identity = WidgetSyncIdentityStore(defaults: defaults).load()
        #expect(identity.currentUserID == firstDayUUID(100))
        #expect(identity.currentDisplayName == "Alex")
        #expect(identity.partnerDisplayName == nil)
    }

    @Test func aDrawingLeftFromEarlierIsNotTheFirstDrawing() async throws {
        let model = makeModel(
            gateway: FirstDayGatewaySpy(),
            canvas: FirstDayCanvasFake(drawingData: Data("old".utf8)),
            defaults: try firstDayTestDefaults()
        )

        await model.load()

        #expect(!model.hasDrawing)
    }
}

struct FirstDayPurgeTests {
    private let drawing = Data("first drawing".utf8)

    private func pending(isFirstDay: Bool) throws -> WidgetPendingUploadSnapshot? {
        let store = WidgetPendingUploadStore(defaults: try firstDayTestDefaults())
        store.markPending(
            firstDayPayload("first drawing"),
            contentHash: WidgetCanvasUploadService.sha256Hex(of: drawing),
            isFirstDay: isFirstDay
        )
        return store.pendingSnapshot
    }

    @Test func anEndedRelationshipKeepsAnUnsentFirstDayDrawingButNotACouplesDrawing() throws {
        let ended = LocalPrivacyPurgeScope.relationshipContentPurged(clearAccessSnapshot: false)

        #expect(LiveLocalPrivateContentPurger.keepsUnsentFirstDayDrawing(
            scope: ended,
            pending: try pending(isFirstDay: true),
            savedDrawing: drawing
        ))
        #expect(!LiveLocalPrivateContentPurger.keepsUnsentFirstDayDrawing(
            scope: ended,
            pending: try pending(isFirstDay: false),
            savedDrawing: drawing
        ))
    }

    @Test func signOutAndAMismatchedDrawingClearTheFirstDayDrawing() throws {
        let firstDay = try pending(isFirstDay: true)

        #expect(!LiveLocalPrivateContentPurger.keepsUnsentFirstDayDrawing(
            scope: .departingUser,
            pending: firstDay,
            savedDrawing: drawing
        ))
        #expect(!LiveLocalPrivateContentPurger.keepsUnsentFirstDayDrawing(
            scope: .relationshipContentPurged(clearAccessSnapshot: true),
            pending: firstDay,
            savedDrawing: Data("another drawing".utf8)
        ))
    }
}

@MainActor
struct FirstDayCanvasDraftAdoptionTests {
    @Test func pairingMovesTheUnsentFirstDayStrokesToTheCouple() {
        let store = InMemoryWidgetDrawingDraftStore()
        let owner = firstDayUUID(100)
        let couple = firstDayUUID(200)
        let firstDayKey = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: owner)
        store.setDraft(Data("strokes".utf8), for: firstDayKey)
        store.setDraftBase("base", for: firstDayKey)

        store.adoptFirstDayDraft(ownerUserID: owner, coupleID: couple)

        let coupleKey = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        #expect(store.draft(for: coupleKey) == Data("strokes".utf8))
        #expect(store.draftBase(for: coupleKey) == "base")
        #expect(store.draft(for: firstDayKey) == nil)
    }

    @Test func aCoupleDraftIsNotReplaced() {
        let store = InMemoryWidgetDrawingDraftStore()
        let owner = firstDayUUID(100)
        let coupleKey = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: firstDayUUID(200))
        let firstDayKey = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: owner)
        store.setDraft(Data("couple".utf8), for: coupleKey)
        store.setDraft(Data("first day".utf8), for: firstDayKey)

        store.adoptFirstDayDraft(ownerUserID: owner, coupleID: firstDayUUID(200))

        #expect(store.draft(for: coupleKey) == Data("couple".utf8))
        #expect(store.draft(for: firstDayKey) == Data("first day".utf8))
    }
}
