import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct WidgetDrawingViewModelTests {
    @Test func startsWithInkingToolAndEnabledColors() throws {
        let viewModel = WidgetDrawingViewModel()

        #expect(viewModel.selectedTool == .pen)
        #expect(viewModel.isColorSelectionEnabled)
        #expect(viewModel.selectedColorChoiceID == "blush")

        let tool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(tool.inkType == .monoline)
        #expect(WidgetDrawingTool.pen.validWidthRange.contains(tool.width))
    }

    @Test func selectedInkingToolUsesCurrentWidth() throws {
        let viewModel = WidgetDrawingViewModel()

        viewModel.selectTool(.pencil)
        viewModel.updateToolWidthFraction(0.5)

        let tool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(tool.inkType == .pencil)
        #expect(tool.width == WidgetDrawingTool.pencil.width(forFraction: 0.5))
    }

    @Test func selectedPresetColorIsPassedToPencilKit() throws {
        let viewModel = WidgetDrawingViewModel()

        let initialTool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(initialTool.color.isEqual(UIColor.paeoniaWidgetDrawing))

        viewModel.selectColorChoice(viewModel.colorChoices[2])

        let pinkTool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(pinkTool.color.isEqual(UIColor.paeoniaAccentSecondary))
    }

    @Test func customBlackAndWhiteColorsArePassedLiterallyToPencilKit() throws {
        let viewModel = WidgetDrawingViewModel()

        viewModel.selectCustomColor(UIColor.white.cgColor)

        let whiteTool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        assertColor(whiteTool.color, red: 1, green: 1, blue: 1)

        viewModel.selectCustomColor(UIColor.black.cgColor)

        let blackTool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        assertColor(blackTool.color, red: 0, green: 0, blue: 0)
    }

    @Test func sliderFractionMapsToToolWidthImmediately() throws {
        let viewModel = WidgetDrawingViewModel()

        viewModel.updateToolWidthFraction(0.7)

        let updatedTool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(abs(updatedTool.width - WidgetDrawingTool.pen.width(forFraction: 0.7)) < 0.000001)
    }

    @Test func fullSliderTravelSpansInkingToolValidWidthRange() throws {
        let viewModel = WidgetDrawingViewModel()

        viewModel.updateToolWidthFraction(0)
        let smallest = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(smallest.width == WidgetDrawingTool.pen.validWidthRange.lowerBound)

        viewModel.updateToolWidthFraction(1)
        let largest = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(largest.width == WidgetDrawingTool.pen.validWidthRange.upperBound)
    }

    @Test func eraserDisablesColorSelectionAndUsesEraserTool() throws {
        let viewModel = WidgetDrawingViewModel()

        viewModel.selectTool(.eraser)

        #expect(!viewModel.isColorSelectionEnabled)

        let tool = try #require(viewModel.pencilKitTool as? PKEraserTool)
        #expect(tool.eraserType == .fixedWidthBitmap)
        #expect(WidgetDrawingTool.eraser.validWidthRange.contains(tool.width))
    }

    @Test func eraserSliderSpansEraserValidWidthRange() throws {
        let viewModel = WidgetDrawingViewModel()
        viewModel.selectTool(.eraser)

        viewModel.updateToolWidthFraction(0)
        let smallest = try #require(viewModel.pencilKitTool as? PKEraserTool)
        #expect(smallest.width == WidgetDrawingTool.eraser.validWidthRange.lowerBound)

        viewModel.updateToolWidthFraction(1)
        let largest = try #require(viewModel.pencilKitTool as? PKEraserTool)
        #expect(largest.width == WidgetDrawingTool.eraser.validWidthRange.upperBound)
    }

    /// The size preview shows the line the canvas draws. Monoline, the pen's
    /// ink, draws twice the width PencilKit is given.
    @Test func penDrawsTwiceItsWidthWhileOtherToolsDrawTheirWidth() {
        #expect(WidgetDrawingTool.pen.drawnWidth(5) == 10)
        #expect(WidgetDrawingTool.pencil.drawnWidth(5) == 5)
        #expect(WidgetDrawingTool.eraser.drawnWidth(5) == 5)
    }

    @Test func colorSelectionIsIgnoredWhileErasing() {
        let viewModel = WidgetDrawingViewModel()
        let pinkChoice = viewModel.colorChoices[2]

        viewModel.selectTool(.eraser)
        viewModel.selectColorChoice(pinkChoice)
        viewModel.selectCustomColor(UIColor.paeoniaAccentSecondary.cgColor)

        #expect(viewModel.selectedColorChoiceID == "blush")
    }

    @Test func canvasUsesLightInterfaceStyleForLiteralInkColors() {
        let canvasView = PKCanvasView()

        canvasView.configureForPaeoniaDrawingCanvas()

        #expect(canvasView.overrideUserInterfaceStyle == .light)
    }

    @Test func emptyCanvasCannotBeSavedOrCleared() {
        let viewModel = WidgetDrawingViewModel(service: WidgetCanvasServiceSpy(), uploader: WidgetCanvasUploadSpy())

        #expect(viewModel.canSave == false)
        #expect(!viewModel.canClear)
    }
}

/// Saving a drawing and what the view model shows while the save runs.
@MainActor
extension WidgetDrawingViewModelTests {
    @Test func saveIsIgnoredWhenCanvasIsEmpty() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())

        await viewModel.save()

        #expect(spy.saveCount == 0)
    }

    @Test func saveSendsDrawingDataToServiceAndConfirms() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: NoOpWidgetCanvasUpload())
        viewModel.drawing = makeNonEmptyDrawing()

        #expect(viewModel.canSave)

        await viewModel.save()

        #expect(spy.saveCount == 1)
        #expect(spy.lastSavedData == viewModel.drawing.dataRepresentation())
        #expect(viewModel.recentlySaved)
        #expect(viewModel.saveFailure == nil)
        #expect(!viewModel.isSaving)
    }

    @Test func saveForwardsAuthorNameToService() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(
            authorName: "Hjalmar",
            service: spy,
            uploader: NoOpWidgetCanvasUpload()
        )
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        #expect(spy.lastAuthorName == "Hjalmar")
    }

    @Test func cannotSaveAgainUntilDrawingChanges() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: NoOpWidgetCanvasUpload())
        viewModel.drawing = makeNonEmptyDrawing()

        #expect(viewModel.canSave)

        await viewModel.save()

        #expect(viewModel.canSave == false)
    }

    @Test func startingAnotherSaveClearsPreviousConfirmationUntilSaveSucceeds() async {
        let service = SuspendedWidgetCanvasService()
        let viewModel = WidgetDrawingViewModel(service: service, uploader: NoOpWidgetCanvasUpload())
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()
        #expect(viewModel.recentlySaved)

        await service.suspendNextSave()
        viewModel.drawing = makeNonEmptyDrawing(seed: 48)

        let saveTask = Task { @MainActor in
            await viewModel.save()
        }

        await service.waitForSuspendedSaveToStart()

        #expect(!viewModel.recentlySaved)

        await service.releaseSuspendedSave()
        await saveTask.value

        #expect(viewModel.recentlySaved)
    }

    @Test func editsMadeWhileSaveIsSuspendedRemainAnUnsavedDraft() async throws {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let service = SuspendedWidgetCanvasService()
        await service.suspendNextSave()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            coupleID: draftTestCoupleID,
            service: service,
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: draftStore
        )
        let savedSnapshot = makeNonEmptyDrawing(seed: 12)
        viewModel.updateDrawing(savedSnapshot)

        let saveTask = Task { @MainActor in
            await viewModel.save()
        }
        await service.waitForSuspendedSaveToStart()

        let newerEdit = makeNonEmptyDrawing(seed: 88)
        viewModel.updateDrawing(newerEdit)
        await service.releaseSuspendedSave()
        await saveTask.value

        #expect(viewModel.hasUnsavedEdits)
        let draftData = try #require(draftStore.draft(for: draftKey(ownerUserID)))
        let restoredDraft = try PKDrawing(data: draftData)
        #expect(restoredDraft.strokes.map(\.renderBounds) == newerEdit.strokes.map(\.renderBounds))
    }

    /// On iPad the canvas fills the height that is left, so it can change size
    /// while a save runs. The sent drawing used to read as "not sent yet".
    @Test func canvasResizedDuringSaveStillCountsAsSent() async {
        let service = SuspendedWidgetCanvasService()
        await service.suspendNextSave()
        let viewModel = WidgetDrawingViewModel(service: service, uploader: NoOpWidgetCanvasUpload())
        viewModel.canvasDidLayout(side: 600)
        viewModel.updateDrawing(makeNonEmptyDrawing(seed: 40))

        let saveTask = Task { @MainActor in
            await viewModel.save()
        }
        await service.waitForSuspendedSaveToStart()
        viewModel.canvasDidLayout(side: 640)
        await service.releaseSuspendedSave()
        await saveTask.value

        #expect(!viewModel.hasUnsavedEdits)
        #expect(!viewModel.canSave)
    }

    @Test func saveEnqueuesUploadWithDrawingMetadata() async throws {
        let uploadSpy = WidgetCanvasUploadSpy()
        let viewModel = WidgetDrawingViewModel(service: WidgetCanvasServiceSpy(), uploader: uploadSpy)
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        let payload = try #require(uploadSpy.enqueued.first)
        #expect(uploadSpy.enqueued.count == 1)
        #expect(payload.drawingData == viewModel.drawing.dataRepresentation())
        #expect(payload.strokeCount == viewModel.drawing.strokes.count)
    }

    @Test func saveUsesSquareShortEdgeForRasterAndUploadCoordinates() async throws {
        let serviceSpy = WidgetCanvasServiceSpy()
        let uploadSpy = WidgetCanvasUploadSpy()
        let viewModel = WidgetDrawingViewModel(service: serviceSpy, uploader: uploadSpy)
        let canvasView = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 360, height: 280))
        viewModel.bindCanvasView(canvasView)
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        #expect(serviceSpy.lastCanvasSize == CGSize(width: 280, height: 280))
        #expect(try #require(uploadSpy.enqueued.first).canvasSide == 280)
    }

    @Test func canvasSideFallsBackUntilCanvasHasStableLayout() {
        #expect(WidgetDrawingViewModel.canvasSide(for: .zero) == WidgetDrawingViewModel.fallbackCanvasSide)
        #expect(WidgetDrawingViewModel.canvasSide(for: CGSize(width: 300, height: 240)) == 240)
    }

    @Test func failedSaveDoesNotEnqueueUpload() async {
        let serviceSpy = WidgetCanvasServiceSpy()
        serviceSpy.saveError = WidgetDrawingTestError.failed
        let uploadSpy = WidgetCanvasUploadSpy()
        let viewModel = WidgetDrawingViewModel(service: serviceSpy, uploader: uploadSpy)
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        #expect(uploadSpy.enqueued.isEmpty)
    }

    @Test func cannotSaveAFreshlyLoadedDrawing() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(!viewModel.drawing.strokes.isEmpty)
        #expect(viewModel.canSave == false)
    }

    @Test func saveSurfacesFailureWithoutConfirmation() async {
        let spy = WidgetCanvasServiceSpy()
        spy.saveError = WidgetDrawingTestError.failed
        let viewModel = WidgetDrawingViewModel(service: spy, uploader: WidgetCanvasUploadSpy())
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        #expect(viewModel.saveFailure != nil)
        #expect(!viewModel.recentlySaved)
        #expect(!viewModel.isSaving)
    }
}

private func assertColor(
    _ color: UIColor,
    red expectedRed: CGFloat,
    green expectedGreen: CGFloat,
    blue expectedBlue: CGFloat
) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    #expect(abs(red - expectedRed) < 0.001)
    #expect(abs(green - expectedGreen) < 0.001)
    #expect(abs(blue - expectedBlue) < 0.001)
    #expect(abs(alpha - 1) < 0.001)
}
