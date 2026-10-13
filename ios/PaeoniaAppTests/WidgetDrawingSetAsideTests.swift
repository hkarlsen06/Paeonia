import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

/// A draft made on a drawing that is no longer on the widgets is kept aside
/// instead of being piled on top of the new drawing.
@MainActor
struct WidgetDrawingSetAsideTests {
    private let owner = UUID()
    private let couple = UUID()

    @Test func oldDraftIsSetAsideWhenTheWidgetsChanged() async throws {
        let store = InMemoryWidgetDrawingDraftStore()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        let oldWidget = setAsideDrawing(at: 10)
        let draft = PKDrawing(strokes: oldWidget.strokes + setAsideDrawing(at: 60).strokes)
        store.setDraft(draft.dataRepresentation(), for: key)
        store.setDraftBase(oldWidget.paeoniaStrokeFingerprint, for: key)
        let newWidget = setAsideDrawing(at: 120)

        let viewModel = makeViewModel(store: store, widget: newWidget)
        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.drawing.paeoniaContentSignature == newWidget.paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing?.paeoniaContentSignature == draft.paeoniaContentSignature)
        #expect(store.draft(for: key) == nil)
        // The set-aside drawing is on disk too, so closing the app keeps it.
        let setAsideKey = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple, slot: .setAside)
        #expect(store.draft(for: setAsideKey) != nil)

        viewModel.discardSetAsideDrawing()
        #expect(viewModel.setAsideDrawing == nil)
        #expect(store.draft(for: setAsideKey) == nil)
    }

    @Test func draftOnTheCurrentWidgetDrawingComesBack() async {
        let store = InMemoryWidgetDrawingDraftStore()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        let widget = setAsideDrawing(at: 10)
        let draft = PKDrawing(strokes: widget.strokes + setAsideDrawing(at: 60).strokes)
        store.setDraft(draft.dataRepresentation(), for: key)
        store.setDraftBase(widget.paeoniaStrokeFingerprint, for: key)

        let viewModel = makeViewModel(store: store, widget: widget)
        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.drawing.paeoniaContentSignature == draft.paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing == nil)
    }

    @Test func draftWithNoRecordedBaseIsSetAside() async {
        let store = InMemoryWidgetDrawingDraftStore()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        let draft = setAsideDrawing(at: 60)
        store.setDraft(draft.dataRepresentation(), for: key)

        // The base write failed, so nobody can tell what the draft builds on.
        // Setting it aside keeps it without piling it on the widget's drawing.
        let viewModel = makeViewModel(store: store, widget: setAsideDrawing(at: 120))
        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.setAsideDrawing?.paeoniaContentSignature == draft.paeoniaContentSignature)
    }

    @Test func savingADraftRecordsTheWidgetDrawingItBuildsOn() async throws {
        let store = InMemoryWidgetDrawingDraftStore()
        let widget = setAsideDrawing(at: 10)
        let viewModel = makeViewModel(store: store, widget: widget)
        await viewModel.loadSavedDrawingIfNeeded()

        let edit = PKDrawing(strokes: widget.strokes + setAsideDrawing(at: 60).strokes)
        viewModel.updateDrawing(edit)
        viewModel.persistDraftIfNeeded()

        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        #expect(store.draftBase(for: key) == widget.paeoniaStrokeFingerprint)
    }

    private func makeViewModel(store: InMemoryWidgetDrawingDraftStore, widget: PKDrawing) -> WidgetDrawingViewModel {
        WidgetDrawingViewModel(
            ownerUserID: owner,
            coupleID: couple,
            service: SetAsideCanvasService(snapshot: WidgetCanvasSnapshot(
                drawingData: widget.dataRepresentation(),
                authorName: "Robin",
                createdAt: Date(timeIntervalSince1970: 2_000)
            )),
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: store
        )
    }
}

private func setAsideDrawing(at origin: CGFloat) -> PKDrawing {
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
    let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + origin)
    let path = PKStrokePath(controlPoints: points, creationDate: createdAt)
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
}

private actor SetAsideCanvasService: WidgetCanvasManaging {
    let snapshot: WidgetCanvasSnapshot?

    init(snapshot: WidgetCanvasSnapshot?) {
        self.snapshot = snapshot
    }

    // The protocol is async. This double answers right away.
    // swiftlint:disable async_without_await
    func loadSavedDrawing() async -> Data? {
        snapshot?.drawingData
    }

    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        snapshot
    }

    func saveDrawing(_: Data, canvasSize _: CGSize, authorName _: String?, createdAt _: Date) async throws {}

    func saveSyncedDrawing(
        _: Data,
        canvasSize _: CGSize,
        authorName _: String?,
        createdAt _: Date,
        revisionID _: UUID
    ) async throws {}

    func clearForPrivacy() async {}

    func hideForPrivacy() async {}
    // swiftlint:enable async_without_await
}

@MainActor
struct WidgetDrawingSetAsideRestoreTests {
    /// Bringing a drawing back used to add it on top of the canvas. It now
    /// replaces the canvas, and unsent work there is kept aside in its place.
    @Test func bringingBackReplacesTheCanvasAndSwapsUnsentWork() async {
        let store = InMemoryWidgetDrawingDraftStore()
        let owner = UUID()
        let couple = UUID()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        let oldWidget = restoreDrawing(at: 10)
        let draft = PKDrawing(strokes: oldWidget.strokes + restoreDrawing(at: 60).strokes)
        store.setDraft(draft.dataRepresentation(), for: key)
        store.setDraftBase(oldWidget.paeoniaStrokeFingerprint, for: key)
        let newWidget = restoreDrawing(at: 120)
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: owner,
            coupleID: couple,
            service: RestoreCanvasService(widget: newWidget),
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: store
        )
        await viewModel.loadSavedDrawingIfNeeded()
        let newerWork = PKDrawing(strokes: newWidget.strokes + restoreDrawing(at: 180).strokes)
        viewModel.updateDrawing(newerWork)

        viewModel.restoreSetAsideDrawing()

        #expect(viewModel.drawing.paeoniaContentSignature == draft.paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing?.paeoniaContentSignature == newerWork.paeoniaContentSignature)

        // Bringing back again swaps them back.
        viewModel.restoreSetAsideDrawing()
        #expect(viewModel.drawing.paeoniaContentSignature == newerWork.paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing?.paeoniaContentSignature == draft.paeoniaContentSignature)
    }

    @Test func nothingIsKeptAsideWhenTheCanvasOnlyShowsTheWidgets() async {
        let store = InMemoryWidgetDrawingDraftStore()
        let owner = UUID()
        let couple = UUID()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        let draft = restoreDrawing(at: 60)
        store.setDraft(draft.dataRepresentation(), for: key)
        store.setDraftBase(PKDrawing().paeoniaStrokeFingerprint, for: key)
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: owner,
            coupleID: couple,
            service: RestoreCanvasService(widget: restoreDrawing(at: 120)),
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: store
        )
        await viewModel.loadSavedDrawingIfNeeded()

        viewModel.restoreSetAsideDrawing()

        #expect(viewModel.drawing.paeoniaContentSignature == draft.paeoniaContentSignature)
        #expect(viewModel.setAsideDrawing == nil)
    }
}

private func restoreDrawing(at origin: CGFloat) -> PKDrawing {
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
    let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + origin)
    let path = PKStrokePath(controlPoints: points, creationDate: createdAt)
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
}

private actor RestoreCanvasService: WidgetCanvasManaging {
    let widget: PKDrawing

    init(widget: PKDrawing) {
        self.widget = widget
    }

    // The protocol is async. This double answers right away.
    // swiftlint:disable async_without_await
    func loadSavedDrawing() async -> Data? {
        widget.dataRepresentation()
    }

    func saveDrawing(_: Data, canvasSize _: CGSize, authorName _: String?, createdAt _: Date) async throws {}

    func saveSyncedDrawing(
        _: Data,
        canvasSize _: CGSize,
        authorName _: String?,
        createdAt _: Date,
        revisionID _: UUID
    ) async throws {}

    func clearForPrivacy() async {}

    func hideForPrivacy() async {}
    // swiftlint:enable async_without_await
}
