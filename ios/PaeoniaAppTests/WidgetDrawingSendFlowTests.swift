import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

// The test doubles mirror async protocols, so some bodies do not await.
// swiftlint:disable async_without_await

/// Strokes racing loads and partner updates, the send status, and drawings from
/// phones with another screen size.
@MainActor
struct WidgetDrawingSendFlowTests {
    /// A stroke drawn while the saved drawing was still loading used to be
    /// replaced by the loaded drawing when the load finished.
    @Test func strokeDrawnWhileTheSavedDrawingLoadsIsKept() async {
        let service = GatedLoadCanvasService()
        await service.setSnapshot(WidgetCanvasSnapshot(
            drawingData: flowDrawing(at: 40).dataRepresentation(),
            authorName: "Robin",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        await service.holdNextLoad()
        let viewModel = WidgetDrawingViewModel(service: service, uploader: FlowUploadSpy())

        let load = Task { await viewModel.loadSavedDrawingIfNeeded() }
        await service.waitUntilLoadIsHeld()
        let stroke = flowDrawing(at: 120)
        viewModel.updateDrawing(stroke, undoManager: nil)
        await service.releaseLoad()
        await load.value

        #expect(viewModel.drawing.paeoniaContentSignature == stroke.paeoniaContentSignature)
        // The loaded drawing still describes the widgets.
        #expect(viewModel.savedDrawingAuthorName == "Robin")
        #expect(viewModel.hasUnsavedEdits)
    }

    /// A partner's drawing arriving while the canvas has unsent changes takes
    /// the canvas, and the changes are kept aside to bring back. Showing both
    /// at once piled one drawing on the other.
    @Test func partnerDrawingDuringUnsentChangesSetsThemAside() async {
        let service = GatedLoadCanvasService()
        await service.setSnapshot(WidgetCanvasSnapshot(
            drawingData: flowDrawing(at: 40).dataRepresentation(),
            authorName: "Alex",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        let viewModel = WidgetDrawingViewModel(service: service, uploader: FlowUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()
        let edit = PKDrawing(strokes: viewModel.drawing.strokes + flowDrawing(at: 150).strokes)
        viewModel.updateDrawing(edit, undoManager: nil)

        await service.setSnapshot(WidgetCanvasSnapshot(
            drawingData: flowDrawing(at: 90).dataRepresentation(),
            authorName: "Robin",
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))
        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        #expect(viewModel.drawing.paeoniaContentSignature == flowDrawing(at: 90).paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing?.paeoniaContentSignature == edit.paeoniaContentSignature)
        #expect(viewModel.partnerSentWhileEditing)
        #expect(viewModel.savedDrawingAuthorName == "Robin")
        #expect(!viewModel.canSave)

        viewModel.restoreSetAsideDrawing()
        #expect(viewModel.drawing.paeoniaContentSignature == edit.paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing == nil)
        #expect(viewModel.canSave)
    }

    /// A partner's drawing must not replace the canvas while a finger is down
    /// for the first stroke (the canvas still looks empty then).
    @Test func partnerDrawingWaitsForTheStrokeInProgress() async {
        let service = GatedLoadCanvasService()
        let viewModel = WidgetDrawingViewModel(service: service, uploader: FlowUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()
        await service.setSnapshot(WidgetCanvasSnapshot(
            drawingData: flowDrawing(at: 90).dataRepresentation(),
            authorName: "Robin",
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))

        viewModel.setDrawingStrokeInProgress(true)
        await viewModel.reloadSavedDrawingFromSyncIfSafe()
        #expect(viewModel.drawing.strokes.isEmpty)

        let stroke = flowDrawing(at: 150)
        viewModel.updateDrawing(stroke, undoManager: nil)
        viewModel.setDrawingStrokeInProgress(false)
        // Lifting the finger runs the deferred check; running it here as well
        // makes the outcome observable without waiting on that task.
        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        #expect(viewModel.drawing.paeoniaContentSignature == flowDrawing(at: 90).paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing?.paeoniaContentSignature == stroke.paeoniaContentSignature)
        #expect(viewModel.partnerSentWhileEditing)
    }

    /// Sending offline used to say "Sent". It now says the drawing waits for
    /// the network, and turns to sent once a background retry gets it out.
    @Test func offlineSendWaitsAndLaterReportsSent() async {
        let uploader = FlowUploadSpy()
        uploader.outcome = .waiting
        let viewModel = WidgetDrawingViewModel(service: GatedLoadCanvasService(), uploader: uploader)
        viewModel.updateDrawing(flowDrawing(at: 60), undoManager: nil)

        await viewModel.save()

        #expect(viewModel.delivery == .waiting)
        #expect(!viewModel.recentlySaved)
        #expect(!viewModel.canSave)

        uploader.pendingUpload = false
        await viewModel.refreshDelivery()
        #expect(viewModel.delivery == .sent)
    }

    @Test func reopeningWithAnUnsentDrawingShowsItIsWaiting() async {
        let uploader = FlowUploadSpy()
        uploader.pendingUpload = true
        let viewModel = WidgetDrawingViewModel(service: GatedLoadCanvasService(), uploader: uploader)

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.delivery == .waiting)
    }

    /// The drawing is marked as not sent before it is shown locally, so a sync
    /// running at the same time cannot pull an older drawing over it.
    @Test func drawingIsMarkedNotSentBeforeItIsPublishedLocally() async {
        let uploader = FlowUploadSpy()
        let service = GatedLoadCanvasService()
        await service.recordSavesInto(uploader)
        let viewModel = WidgetDrawingViewModel(service: service, uploader: uploader)
        viewModel.updateDrawing(flowDrawing(at: 60), undoManager: nil)

        await viewModel.save()

        #expect(uploader.events == ["markPending", "publish", "send"])
    }

    /// A drawing made on a bigger screen used to be cut off at the right and
    /// bottom edges on a smaller one.
    @Test func drawingFromABiggerScreenIsScaledToFit() async {
        let service = GatedLoadCanvasService()
        let partnerDrawing = flowDrawing(at: 380)
        await service.setSnapshot(WidgetCanvasSnapshot(
            drawingData: partnerDrawing.dataRepresentation(),
            authorName: "Robin",
            createdAt: Date(timeIntervalSince1970: 1_000),
            canvasSide: 400
        ))
        let viewModel = WidgetDrawingViewModel(service: service, uploader: FlowUploadSpy())

        viewModel.canvasDidLayout(side: 300)
        await viewModel.loadSavedDrawingIfNeeded()

        let bounds = viewModel.drawing.bounds
        #expect(bounds.maxX <= 300)
        #expect(bounds.maxY <= 300)
        // Fitting the drawing to the screen is not an edit.
        #expect(!viewModel.hasUnsavedEdits)
        #expect(!viewModel.canSave)
    }

    @Test func resizingTheCanvasKeepsTheDrawingAndIsNotAnEdit() async {
        let service = GatedLoadCanvasService()
        await service.setSnapshot(WidgetCanvasSnapshot(
            drawingData: flowDrawing(at: 200).dataRepresentation(),
            authorName: "Robin",
            createdAt: Date(timeIntervalSince1970: 1_000),
            canvasSide: 300
        ))
        let viewModel = WidgetDrawingViewModel(service: service, uploader: FlowUploadSpy())
        viewModel.canvasDidLayout(side: 300)
        await viewModel.loadSavedDrawingIfNeeded()
        let revision = viewModel.drawingRevision

        viewModel.canvasDidLayout(side: 360)

        #expect(viewModel.drawingRevision > revision)
        #expect(!viewModel.hasUnsavedEdits)
        #expect(viewModel.drawing.bounds.midX > 200)
    }

    // MARK: - Drafts

    /// A draft holds whatever was on the canvas, which can include an
    /// ex-partner's strokes. It must never show up for another couple.
    @Test func draftFromAnotherCoupleIsNeverShown() async {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let firstCouple = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: UUID(),
            service: GatedLoadCanvasService(),
            uploader: FlowUploadSpy(),
            draftStore: draftStore
        )
        firstCouple.updateDrawing(flowDrawing(at: 60), undoManager: nil)
        firstCouple.persistDraftIfNeeded()

        let nextCouple = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: UUID(),
            service: GatedLoadCanvasService(),
            uploader: FlowUploadSpy(),
            draftStore: draftStore
        )
        await nextCouple.loadSavedDrawingIfNeeded()

        #expect(nextCouple.drawing.strokes.isEmpty)
    }

    /// Unpairing while the drawing screen stays open used to write the draft
    /// back right after the privacy purge removed it.
    @Test func screenOpenDuringAPurgeDoesNotWriteItsDraftBack() async {
        let ownerUserID = UUID()
        let coupleID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            service: GatedLoadCanvasService(),
            uploader: FlowUploadSpy(),
            draftStore: draftStore
        )
        viewModel.updateDrawing(flowDrawing(at: 60), undoManager: nil)

        draftStore.clearDraft(for: ownerUserID)
        viewModel.persistDraftIfNeeded()

        #expect(draftStore.draft(for: WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: coupleID)) == nil)
    }

    @Test func withoutACoupleNoDraftIsKept() {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            service: GatedLoadCanvasService(),
            uploader: FlowUploadSpy(),
            draftStore: draftStore
        )
        viewModel.updateDrawing(flowDrawing(at: 60), undoManager: nil)

        viewModel.persistDraftIfNeeded()

        #expect(draftStore.draft(for: WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: UUID())) == nil)
    }

    @Test func fileDraftStoreKeepsOneDraftPerCoupleAndThePurgeRemovesAll() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDrawingSendFlowTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileWidgetDrawingDraftStore(directoryURL: directoryURL)
        let ownerUserID = UUID()
        let firstKey = WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: UUID())
        let secondKey = WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: UUID())
        // A draft from a build that kept one file per person.
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let legacyURL = directoryURL.appendingPathComponent("\(ownerUserID.uuidString.lowercased()).drawing")
        try Data([0x09]).write(to: legacyURL)

        store.setDraft(Data([0x01]), for: firstKey)
        store.setDraft(Data([0x02]), for: secondKey)
        #expect(store.draft(for: firstKey) == Data([0x01]))
        #expect(store.draft(for: secondKey) == Data([0x02]))

        let generation = store.purgeGeneration(for: ownerUserID)
        store.clearDraft(for: ownerUserID)

        #expect(store.draft(for: firstKey) == nil)
        #expect(store.draft(for: secondKey) == nil)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(store.purgeGeneration(for: ownerUserID) == generation + 1)
    }

    /// An unsent drawing saved by a build that kept one draft per person is
    /// moved to the current couple when the drawing screen opens, not dropped.
    @Test func legacyDraftMovesToTheCurrentCouple() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDrawingSendFlowTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileWidgetDrawingDraftStore(directoryURL: directoryURL)
        let ownerUserID = UUID()
        let coupleID = UUID()
        let legacyDrawing = flowDrawing(at: 70)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let legacyURL = directoryURL.appendingPathComponent("\(ownerUserID.uuidString.lowercased()).drawing")
        try legacyDrawing.dataRepresentation().write(to: legacyURL)
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            service: GatedLoadCanvasService(),
            uploader: FlowUploadSpy(),
            draftStore: store
        )

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.drawing.paeoniaContentSignature == legacyDrawing.paeoniaContentSignature)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        let key = WidgetDrawingDraftKey(ownerUserID: ownerUserID, coupleID: coupleID)
        let movedDraft = try #require(store.draft(for: key))
        #expect(try PKDrawing(data: movedDraft).paeoniaContentSignature == legacyDrawing.paeoniaContentSignature)
    }

    @Test func drawingLimitsMatchTheServer() {
        #expect(WidgetDrawingLimits.allows(byteCount: 2_097_152, strokeCount: 5_000, pointCount: 200_000))
        #expect(!WidgetDrawingLimits.allows(byteCount: 2_097_153, strokeCount: 1, pointCount: 1))
        #expect(!WidgetDrawingLimits.allows(byteCount: 1, strokeCount: 5_001, pointCount: 1))
        #expect(!WidgetDrawingLimits.allows(byteCount: 1, strokeCount: 1, pointCount: 200_001))
    }
}

private func flowDrawing(at origin: CGFloat) -> PKDrawing {
    let locations = [CGPoint(x: origin, y: origin), CGPoint(x: origin + 10, y: origin + 10)]
    let points = locations.enumerated().map { index, location in
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
    // A distinct creation time per origin keeps stroke keys apart.
    let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + origin)
    let path = PKStrokePath(controlPoints: points, creationDate: createdAt)
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
}

private final class FlowUploadSpy: WidgetCanvasUploading, @unchecked Sendable {
    private(set) var events: [String] = []
    var outcome: WidgetDrawingDelivery = .delivered
    var pendingUpload = false

    var hasPendingUpload: Bool {
        pendingUpload
    }

    func record(_ event: String) {
        events.append(event)
    }

    func markPending(_: WidgetDrawingUploadPayload) -> WidgetPendingUploadSnapshot? {
        events.append("markPending")
        return nil
    }

    func send(_: WidgetDrawingUploadPayload) -> WidgetDrawingDelivery {
        events.append("send")
        pendingUpload = outcome == .waiting
        return outcome
    }

    func uploadPending(_: WidgetDrawingUploadPayload) async throws {}
}

/// A canvas service whose load can be held open by the test.
private actor GatedLoadCanvasService: WidgetCanvasManaging {
    private var snapshot: WidgetCanvasSnapshot?
    private var holdsNextLoad = false
    private var heldLoad: CheckedContinuation<Void, Never>?
    private var saveRecorder: FlowUploadSpy?

    func setSnapshot(_ snapshot: WidgetCanvasSnapshot?) {
        self.snapshot = snapshot
    }

    func holdNextLoad() {
        holdsNextLoad = true
    }

    func recordSavesInto(_ recorder: FlowUploadSpy) {
        saveRecorder = recorder
    }

    func waitUntilLoadIsHeld() async {
        while heldLoad == nil {
            await Task.yield()
        }
    }

    func releaseLoad() {
        heldLoad?.resume()
        heldLoad = nil
    }

    func loadSavedDrawing() async -> Data? {
        snapshot?.drawingData
    }

    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        if holdsNextLoad {
            holdsNextLoad = false
            await withCheckedContinuation { heldLoad = $0 }
        }
        return snapshot
    }

    func saveDrawing(_ drawingData: Data, canvasSize: CGSize, authorName: String?, createdAt: Date) async throws {
        if let saveRecorder {
            await MainActor.run { saveRecorder.record("publish") }
        }
        snapshot = WidgetCanvasSnapshot(
            drawingData: drawingData,
            authorName: authorName,
            createdAt: createdAt,
            canvasSide: canvasSize.width
        )
    }

    func clearForPrivacy() async {
        snapshot = nil
    }
}

// swiftlint:enable async_without_await
