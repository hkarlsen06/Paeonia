import Foundation
import PencilKit
import Testing
import UIKit
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
            pushAuthorization: push,
            identityStore: WidgetSyncIdentityStore(defaults: defaults),
            questionPreferences: FirstDayPreferencesFake()
        )
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

    /// The drawing made on the welcome flow's drawing screen before there is an account
    /// is sent to the first day draft when the invite screen loads after sign-in.
    @Test func aDrawingMadeBeforeSignInGoesToTheDraftWhenTheInviteScreenLoads() async throws {
        let defaults = try firstDayTestDefaults()
        let canvas = FirstDayCanvasFake()
        let pendingStore = WidgetPendingUploadStore(defaults: defaults)
        let welcome = WelcomeFlowModel(
            store: InMemoryWelcomeFlowStore(),
            funnel: NoOpWelcomeFunnelRecorder(),
            canvas: canvas,
            pendingUploads: pendingStore,
            drawingDrafts: InMemoryWidgetDrawingDraftStore(),
            phoneHasNoOtherAccount: { true }
        )
        let drawingViewModel = welcome.drawingViewModel()
        drawingViewModel.updateDrawing(firstDayStroke())
        await drawingViewModel.save()

        #expect(drawingViewModel.delivery == .sent)
        #expect(welcome.hasWaitingDrawing)
        #expect(await canvas.loadSavedDrawing() != nil)

        let gateway = FirstDayGatewaySpy()
        await makeModel(gateway: gateway, canvas: canvas, defaults: defaults).load()

        // The draft is read again after the save, so the share text can name the drawing.
        #expect(await gateway.steps.suffix(5) == ["reserve", "upload", "finalize", "save", "start"])
        #expect(!pendingStore.hasPending)
    }
}

private func firstDayStroke() -> PKDrawing {
    let points = [CGPoint(x: 40, y: 40), CGPoint(x: 80, y: 80)].enumerated().map { index, location in
        PKStrokePoint(
            location: location,
            timeOffset: TimeInterval(index) * 0.01,
            size: CGSize(width: 4, height: 4),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
    }
    let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000))
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
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
