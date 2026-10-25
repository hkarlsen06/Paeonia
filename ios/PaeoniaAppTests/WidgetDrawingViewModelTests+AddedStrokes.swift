import PencilKit
import Testing
@testable import PaeoniaApp

/// Strokes from another screen, such as the welcome widget's doodle, joining the canvas.
@MainActor
extension WidgetDrawingViewModelTests {
    @Test func strokesAddedBeforeLoadingLandOnTheDraftAndUndoOneAtATime() async throws {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let draft = makeNonEmptyDrawing(seed: 40)
        draftStore.setDraft(draft.dataRepresentation(), for: draftKey(ownerUserID))
        draftStore.setDraftBase(PKDrawing().paeoniaStrokeFingerprint, for: draftKey(ownerUserID))
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: WidgetCanvasServiceSpy(),
            uploader: WidgetCanvasUploadSpy(),
            draftStore: draftStore
        )
        let doodle = PKDrawing(strokes: [
            addedStroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20), createdAt: 1),
            addedStroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 70), createdAt: 2),
        ])
        var addedCount = 0

        // Handed over before the canvas loads, so they must wait for the draft.
        viewModel.addStrokesOnceLoaded(doodle, side: 100) { addedCount += 1 }
        #expect(viewModel.drawing.strokes.isEmpty)
        await viewModel.loadSavedDrawingIfNeeded()

        #expect(addedCount == 1)
        #expect(viewModel.drawing.strokes.count == 3)
        #expect(viewModel.drawing.strokes[0].renderBounds == draft.strokes[0].renderBounds)
        // Scaled from the 100-point doodle to the canvas, which has no layout here.
        let scale = WidgetDrawingViewModel.fallbackCanvasSide / 100
        let firstAdded = viewModel.drawing.strokes[1].renderBounds
        #expect(abs(firstAdded.midX - doodle.strokes[0].renderBounds.midX * scale) < 1)
        #expect(abs(firstAdded.midY - doodle.strokes[0].renderBounds.midY * scale) < 1)
        // Written to the draft at once, so a relaunch keeps them.
        let savedDraft = try PKDrawing(data: try #require(draftStore.draft(for: draftKey(ownerUserID))))
        #expect(savedDraft.strokes.count == 3)

        viewModel.undoDrawing()
        #expect(viewModel.drawing.strokes.count == 2)
        viewModel.undoDrawing()
        #expect(viewModel.drawing.strokes.count == 1)
        // A restored draft's own strokes are not undo steps.
        #expect(!viewModel.canUndoDrawing)
    }

    private func addedStroke(from start: CGPoint, to end: CGPoint, createdAt: TimeInterval) -> PKStroke {
        let points = [start, end].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 0
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: createdAt))
        return PKStroke(ink: PKInk(.monoline, color: .paeoniaWidgetDrawing), path: path)
    }
}
