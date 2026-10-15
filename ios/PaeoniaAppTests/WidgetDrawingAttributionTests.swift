import PencilKit
import Testing
@testable import PaeoniaApp

/// Canvas attribution + edited-state behavior (name/timestamp + strikethrough).
@MainActor
struct WidgetDrawingAttributionTests {
    @Test func savingSetsAttributionAndClearsEdits() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(
            authorName: "Me",
            service: spy,
            uploader: WidgetCanvasUploadSpy()
        )
        viewModel.drawing = makeNonEmptyDrawing()
        #expect(viewModel.hasUnsavedEdits)

        await viewModel.save()

        #expect(spy.saveCount == 1)
        #expect(viewModel.savedDrawingAuthorName == "Me")
        #expect(viewModel.savedDrawingCreatedAt != nil)
        #expect(viewModel.hasUnsavedEdits == false)
        #expect(viewModel.isShowingSavedAttribution)
    }

    @Test func editingAfterSaveMarksUnsavedButKeepsAttribution() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(
            authorName: "Me",
            service: spy,
            uploader: WidgetCanvasUploadSpy()
        )
        viewModel.drawing = makeNonEmptyDrawing()
        await viewModel.save()
        #expect(viewModel.hasUnsavedEdits == false)

        // A different drawing differs from what was just saved.
        viewModel.drawing = makeNonEmptyDrawing(seed: 48)

        #expect(viewModel.hasUnsavedEdits)
        #expect(viewModel.isShowingSavedAttribution)
        #expect(viewModel.savedDrawingAuthorName == "Me")
    }

    @Test func clearingAfterSaveKeepsLastSavedAttribution() async {
        let savedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        spy.savedAuthorName = "Partner"
        spy.savedCreatedAt = savedAt
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()

        viewModel.clearCanvas()

        #expect(viewModel.drawing.strokes.isEmpty)
        #expect(viewModel.hasUnsavedEdits)
        #expect(viewModel.isShowingSavedAttribution)
        #expect(viewModel.savedDrawingAuthorName == "Partner")
        #expect(viewModel.savedDrawingCreatedAt == savedAt)
    }

    @Test func identicalSyncedDrawingRefreshesItsAttribution() async {
        let drawingData = makeNonEmptyDrawing().dataRepresentation()
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = drawingData
        spy.savedAuthorName = "Me"
        spy.savedCreatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()

        let partnerSavedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        spy.savedAuthorName = "Partner"
        spy.savedCreatedAt = partnerSavedAt

        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        #expect(viewModel.savedDrawingAuthorName == "Partner")
        #expect(viewModel.savedDrawingCreatedAt == partnerSavedAt)
        #expect(viewModel.hasUnsavedEdits == false)
    }

    @Test func missingMetadataForIdenticalDrawingDoesNotEraseKnownAttribution() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        spy.savedAuthorName = "Partner"
        spy.savedCreatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()

        spy.savedAuthorName = nil
        spy.savedCreatedAt = nil
        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        #expect(viewModel.savedDrawingAuthorName == "Partner")
        #expect(viewModel.savedDrawingCreatedAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(viewModel.isShowingSavedAttribution)
    }

    @Test func identicalSaveWithUnknownAuthorDoesNotKeepPreviousAuthor() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        spy.savedAuthorName = "Me"
        spy.savedCreatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()

        let latestSavedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        spy.savedAuthorName = nil
        spy.savedCreatedAt = latestSavedAt
        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        #expect(viewModel.savedDrawingAuthorName == nil)
        #expect(viewModel.savedDrawingCreatedAt == latestSavedAt)
        #expect(viewModel.isShowingSavedAttribution)
    }

    @Test func firstUnsavedDrawingHasNoAttribution() {
        let viewModel = WidgetDrawingViewModel(service: WidgetCanvasServiceSpy(), uploader: WidgetCanvasUploadSpy())

        viewModel.drawing = makeNonEmptyDrawing()

        #expect(viewModel.hasUnsavedEdits)
        #expect(!viewModel.isShowingSavedAttribution)
        #expect(viewModel.savedDrawingAuthorName == nil)
        #expect(viewModel.savedDrawingCreatedAt == nil)
    }

    @Test func undoingEditsBackToSavedStateClearsUnsavedEdits() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(
            authorName: "Me",
            service: spy,
            uploader: WidgetCanvasUploadSpy()
        )
        let baseline = makeNonEmptyDrawing()
        viewModel.drawing = baseline
        await viewModel.save()
        #expect(viewModel.hasUnsavedEdits == false)

        // Add a stroke on top of the saved drawing.
        viewModel.drawing = PKDrawing(strokes: baseline.strokes + makeNonEmptyDrawing(seed: 80).strokes)
        #expect(viewModel.hasUnsavedEdits)

        // Undo back to exactly the saved strokes — should read as unedited again.
        viewModel.drawing = PKDrawing(strokes: baseline.strokes)
        #expect(viewModel.hasUnsavedEdits == false)
        #expect(viewModel.canSave == false)
    }

    @Test func reencodedIdenticalDrawingDoesNotReadAsEdit() async throws {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(
            authorName: "Me",
            service: spy,
            uploader: WidgetCanvasUploadSpy()
        )
        viewModel.drawing = makeNonEmptyDrawing(seed: 20)
        await viewModel.save()
        #expect(viewModel.hasUnsavedEdits == false)

        // PencilKit re-emits committed strokes from serialized data after save.
        // That must not read as a fresh, savable edit.
        let savedData = try #require(spy.lastSavedData)
        viewModel.drawing = try PKDrawing(data: savedData)
        #expect(viewModel.hasUnsavedEdits == false)
        #expect(viewModel.canSave == false)

        // A real change still registers.
        viewModel.drawing = makeNonEmptyDrawing(seed: 48)
        #expect(viewModel.hasUnsavedEdits)
        #expect(viewModel.canSave)
    }

    @Test func loadingAppliesSavedAttribution() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        spy.savedAuthorName = "Partner"
        spy.savedCreatedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.savedDrawingAuthorName == "Partner")
        #expect(viewModel.savedDrawingCreatedAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(viewModel.hasUnsavedEdits == false)
        #expect(viewModel.isShowingSavedAttribution)
    }
}
