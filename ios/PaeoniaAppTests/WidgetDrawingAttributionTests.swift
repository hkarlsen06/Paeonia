import PencilKit
import Testing
@testable import PaeoniaApp

/// Edited-state detection for the drawing canvas.
@MainActor
struct WidgetDrawingAttributionTests {
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
}
