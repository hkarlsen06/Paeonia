import PencilKit
import Testing
@testable import PaeoniaApp

/// Clearing, loading, unfinished drafts and reloading from sync.
@MainActor
extension WidgetDrawingViewModelTests {
    @Test func loadSavedDrawingDoesNotClobberInProgressWork() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        let inProgress = makeNonEmptyDrawing()
        viewModel.drawing = inProgress

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.drawing.dataRepresentation() == inProgress.dataRepresentation())
    }

    @Test func unfinishedDrawingRestoresForTheSameOwner() async {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let inProgress = makeNonEmptyDrawing(seed: 72)
        let firstViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: WidgetCanvasServiceSpy(),
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )

        firstViewModel.updateDrawing(inProgress)
        firstViewModel.persistDraftIfNeeded()

        let reopenedViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: WidgetCanvasServiceSpy(),
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )
        await reopenedViewModel.loadSavedDrawingIfNeeded()

        #expect(reopenedViewModel.drawing.strokes.map(\.renderBounds) == inProgress.strokes.map(\.renderBounds))
        #expect(reopenedViewModel.hasUnsavedEdits)
    }

    @Test func draftNeverCrossesOwnerBoundary() async {
        let firstOwnerUserID = UUID()
        let secondOwnerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let firstViewModel = WidgetDrawingViewModel(
            ownerUserID: firstOwnerUserID,
            coupleID: draftTestCoupleID,
            service: WidgetCanvasServiceSpy(),
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )
        firstViewModel.updateDrawing(makeNonEmptyDrawing())
        firstViewModel.persistDraftIfNeeded()

        let secondViewModel = WidgetDrawingViewModel(
            ownerUserID: secondOwnerUserID,
            coupleID: draftTestCoupleID,
            service: WidgetCanvasServiceSpy(),
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )
        await secondViewModel.loadSavedDrawingIfNeeded()

        #expect(secondViewModel.drawing.strokes.isEmpty)
        #expect(draftStore.draft(for: draftKey(firstOwnerUserID)) != nil)
        #expect(draftStore.draft(for: draftKey(secondOwnerUserID)) == nil)
    }

    @Test func successfulSaveClearsTheOwnersDraft() async {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: WidgetCanvasServiceSpy(),
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: draftStore
        )
        viewModel.updateDrawing(makeNonEmptyDrawing())
        viewModel.persistDraftIfNeeded()
        #expect(draftStore.draft(for: draftKey(ownerUserID)) != nil)

        await viewModel.save()

        #expect(draftStore.draft(for: draftKey(ownerUserID)) == nil)
    }

    @Test func clearingSavedDrawingRestoresAsAnEmptyUnsavedDraft() async {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let service = WidgetCanvasServiceSpy()
        service.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        let firstViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: service,
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )
        await firstViewModel.loadSavedDrawingIfNeeded()

        firstViewModel.clearCanvas()

        let reopenedViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: service,
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )
        await reopenedViewModel.loadSavedDrawingIfNeeded()

        #expect(reopenedViewModel.drawing.strokes.isEmpty)
        #expect(reopenedViewModel.hasUnsavedEdits)
    }

    @Test func reloadFromSyncAppliesNewerDrawingWhenNoEdits() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing(seed: 12).dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()
        #expect(viewModel.hasUnsavedEdits == false)
        let originalSignature = PKDrawing(strokes: viewModel.drawing.strokes).dataRepresentation()

        // A partner's newer drawing syncs into local storage.
        spy.savedDrawingData = makeNonEmptyDrawing(seed: 99).dataRepresentation()
        spy.savedAuthorName = "Partner"

        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        let reloadedSignature = PKDrawing(strokes: viewModel.drawing.strokes).dataRepresentation()
        #expect(reloadedSignature != originalSignature)
        #expect(viewModel.savedDrawingAuthorName == "Partner")
        #expect(viewModel.hasUnsavedEdits == false)
    }
}
