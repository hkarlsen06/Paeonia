import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

// The widget canvas test double mirrors an async protocol, so its synchronous
// bodies do not await. This matches the project's other test doubles.
// swiftlint:disable async_without_await

@MainActor
struct WidgetDrawingViewModelTests {
    @Test func startsWithInkingToolAndEnabledColors() throws {
        let viewModel = WidgetDrawingViewModel()

        #expect(viewModel.selectedTool == .pen)
        #expect(viewModel.isColorSelectionEnabled)
        #expect(viewModel.selectedColorChoiceID == "blush")

        let tool = try #require(viewModel.pencilKitTool as? PKInkingTool)
        #expect(tool.inkType == .pen)
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

    @Test func colorSelectionIsIgnoredWhileErasing() {
        let viewModel = WidgetDrawingViewModel()
        let pinkChoice = viewModel.colorChoices[2]

        viewModel.selectTool(.eraser)
        viewModel.selectColorChoice(pinkChoice)
        viewModel.selectCustomColor(UIColor.paeoniaAccentSecondary.cgColor)

        #expect(viewModel.selectedColorChoiceID == "blush")
    }

    @Test func undoAvailabilityFollowsProvidedUndoManager() {
        let viewModel = WidgetDrawingViewModel()
        let undoManager = UndoManager()
        let target = WidgetDrawingUndoTestTarget()

        undoManager.registerUndo(withTarget: target) { _ in }
        viewModel.updateDrawing(PKDrawing(), undoManager: undoManager)

        #expect(viewModel.canUndoDrawing)
        #expect(!viewModel.canRedoDrawing)
    }

    @Test func canvasUsesLightInterfaceStyleForLiteralInkColors() {
        let canvasView = PKCanvasView()

        canvasView.configureForPaeoniaDrawingCanvas()

        #expect(canvasView.overrideUserInterfaceStyle == .light)
    }

    @Test func emptyCanvasCannotBeSavedOrCleared() {
        let viewModel = WidgetDrawingViewModel(service: WidgetCanvasServiceSpy())

        #expect(viewModel.canSave == false)
        #expect(!viewModel.canClear)
    }

    @Test func saveIsIgnoredWhenCanvasIsEmpty() async {
        let spy = WidgetCanvasServiceSpy()
        let viewModel = WidgetDrawingViewModel(service: spy)

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
            service: service,
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: draftStore
        )
        let savedSnapshot = makeNonEmptyDrawing(seed: 12)
        viewModel.updateDrawing(savedSnapshot, undoManager: nil)

        let saveTask = Task { @MainActor in
            await viewModel.save()
        }
        await service.waitForSuspendedSaveToStart()

        let newerEdit = makeNonEmptyDrawing(seed: 88)
        viewModel.updateDrawing(newerEdit, undoManager: nil)
        await service.releaseSuspendedSave()
        await saveTask.value

        #expect(viewModel.hasUnsavedEdits)
        let draftData = try #require(draftStore.draft(for: ownerUserID))
        let restoredDraft = try PKDrawing(data: draftData)
        #expect(restoredDraft.strokes.map(\.renderBounds) == newerEdit.strokes.map(\.renderBounds))
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
        let viewModel = WidgetDrawingViewModel(service: spy)

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(!viewModel.drawing.strokes.isEmpty)
        #expect(viewModel.canSave == false)
    }

    @Test func saveSurfacesFailureWithoutConfirmation() async {
        let spy = WidgetCanvasServiceSpy()
        spy.saveError = WidgetDrawingTestError.failed
        let viewModel = WidgetDrawingViewModel(service: spy)
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        #expect(viewModel.saveFailure != nil)
        #expect(!viewModel.recentlySaved)
        #expect(!viewModel.isSaving)
    }

    @Test func clearCanvasEmptiesDrawing() {
        let viewModel = WidgetDrawingViewModel(service: WidgetCanvasServiceSpy())
        viewModel.drawing = makeNonEmptyDrawing()

        #expect(viewModel.canClear)

        viewModel.clearCanvas()

        #expect(viewModel.drawing.strokes.isEmpty)
        #expect(viewModel.canSave == false)
        #expect(!viewModel.canClear)
    }

    @Test func loadSavedDrawingLoadsPersistedDataOnce() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy)

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(spy.loadCount == 1)
        #expect(!viewModel.drawing.strokes.isEmpty)

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(spy.loadCount == 1)
    }

    @Test func loadSavedDrawingDoesNotClobberInProgressWork() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy)
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
            service: WidgetCanvasServiceSpy(),
            draftStore: draftStore
        )

        firstViewModel.updateDrawing(inProgress, undoManager: nil)
        firstViewModel.persistDraftIfNeeded()

        let reopenedViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            service: WidgetCanvasServiceSpy(),
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
            service: WidgetCanvasServiceSpy(),
            draftStore: draftStore
        )
        firstViewModel.updateDrawing(makeNonEmptyDrawing(), undoManager: nil)
        firstViewModel.persistDraftIfNeeded()

        let secondViewModel = WidgetDrawingViewModel(
            ownerUserID: secondOwnerUserID,
            service: WidgetCanvasServiceSpy(),
            draftStore: draftStore
        )
        await secondViewModel.loadSavedDrawingIfNeeded()

        #expect(secondViewModel.drawing.strokes.isEmpty)
        #expect(draftStore.draft(for: firstOwnerUserID) != nil)
        #expect(draftStore.draft(for: secondOwnerUserID) == nil)
    }

    @Test func successfulSaveClearsTheOwnersDraft() async {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            service: WidgetCanvasServiceSpy(),
            uploader: NoOpWidgetCanvasUpload(),
            draftStore: draftStore
        )
        viewModel.updateDrawing(makeNonEmptyDrawing(), undoManager: nil)
        viewModel.persistDraftIfNeeded()
        #expect(draftStore.draft(for: ownerUserID) != nil)

        await viewModel.save()

        #expect(draftStore.draft(for: ownerUserID) == nil)
    }

    @Test func drawingUpdatesWaitForTheDebouncedDraftWriteUntilFlushed() {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            service: WidgetCanvasServiceSpy(),
            draftStore: draftStore
        )

        viewModel.updateDrawing(makeNonEmptyDrawing(), undoManager: nil)

        #expect(draftStore.draft(for: ownerUserID) == nil)
        viewModel.persistDraftIfNeeded()
        #expect(draftStore.draft(for: ownerUserID) != nil)
    }

    @Test func fileDraftStoreScopesAndClearsDraftsByOwner() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDrawingDraftStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FileWidgetDrawingDraftStore(directoryURL: directoryURL)
        let firstOwnerUserID = UUID()
        let secondOwnerUserID = UUID()
        let draft = Data([0x01, 0x02, 0x03])

        store.setDraft(draft, for: firstOwnerUserID)

        #expect(store.draft(for: firstOwnerUserID) == draft)
        #expect(store.draft(for: secondOwnerUserID) == nil)
        store.clearDraft(for: firstOwnerUserID)
        #expect(store.draft(for: firstOwnerUserID) == nil)
    }

    @Test func clearingSavedDrawingRestoresAsAnEmptyUnsavedDraft() async {
        let ownerUserID = UUID()
        let draftStore = InMemoryWidgetDrawingDraftStore()
        let service = WidgetCanvasServiceSpy()
        service.savedDrawingData = makeNonEmptyDrawing().dataRepresentation()
        let firstViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            service: service,
            draftStore: draftStore
        )
        await firstViewModel.loadSavedDrawingIfNeeded()

        firstViewModel.clearCanvas()

        let reopenedViewModel = WidgetDrawingViewModel(
            ownerUserID: ownerUserID,
            service: service,
            draftStore: draftStore
        )
        await reopenedViewModel.loadSavedDrawingIfNeeded()

        #expect(reopenedViewModel.drawing.strokes.isEmpty)
        #expect(reopenedViewModel.hasUnsavedEdits)
    }

    @Test func reloadFromSyncAppliesNewerDrawingWhenNoEdits() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing(seed: 12).dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy)
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

    @Test func reloadFromSyncSkipsWhenUnsavedEdits() async {
        let spy = WidgetCanvasServiceSpy()
        spy.savedDrawingData = makeNonEmptyDrawing(seed: 12).dataRepresentation()
        let viewModel = WidgetDrawingViewModel(service: spy)
        await viewModel.loadSavedDrawingIfNeeded()

        // The user has started drawing on top of the loaded drawing.
        viewModel.drawing = PKDrawing(strokes: viewModel.drawing.strokes + makeNonEmptyDrawing(seed: 77).strokes)
        #expect(viewModel.hasUnsavedEdits)
        let editedStrokeBounds = viewModel.drawing.strokes.map(\.renderBounds)

        // A partner's drawing syncs in; it must not clobber the in-progress work.
        spy.savedDrawingData = makeNonEmptyDrawing(seed: 99).dataRepresentation()
        await viewModel.reloadSavedDrawingFromSyncIfSafe()

        #expect(viewModel.drawing.strokes.map(\.renderBounds) == editedStrokeBounds)
    }

}

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
        let viewModel = WidgetDrawingViewModel(service: spy)
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
        let viewModel = WidgetDrawingViewModel(service: spy)
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
        let viewModel = WidgetDrawingViewModel(service: spy)
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
        let viewModel = WidgetDrawingViewModel(service: spy)
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
        let viewModel = WidgetDrawingViewModel(service: WidgetCanvasServiceSpy())

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
        let viewModel = WidgetDrawingViewModel(service: spy)

        await viewModel.loadSavedDrawingIfNeeded()

        #expect(viewModel.savedDrawingAuthorName == "Partner")
        #expect(viewModel.savedDrawingCreatedAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(viewModel.hasUnsavedEdits == false)
        #expect(viewModel.isShowingSavedAttribution)
    }
}

private func makeNonEmptyDrawing(seed: CGFloat = 12) -> PKDrawing {
    let point = PKStrokePoint(
        location: CGPoint(x: seed, y: seed),
        timeOffset: 0,
        size: CGSize(width: 4, height: 4),
        opacity: 1,
        force: 1,
        azimuth: 0,
        altitude: 0
    )
    let path = PKStrokePath(controlPoints: [point], creationDate: Date())
    let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
    return PKDrawing(strokes: [stroke])
}

private enum WidgetDrawingTestError: Error {
    case failed
}

private final class WidgetCanvasServiceSpy: WidgetCanvasManaging, @unchecked Sendable {
    private(set) var saveCount = 0
    private(set) var loadCount = 0
    private(set) var clearCount = 0
    private(set) var lastSavedData: Data?
    private(set) var lastCanvasSize: CGSize?
    private(set) var lastAuthorName: String?
    var saveError: Error?
    var savedDrawingData: Data?
    var savedAuthorName: String?
    var savedCreatedAt: Date?

    func loadSavedDrawing() async -> Data? {
        savedDrawingData
    }

    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        loadCount += 1
        guard let savedDrawingData else {
            return nil
        }
        return WidgetCanvasSnapshot(
            drawingData: savedDrawingData,
            authorName: savedAuthorName,
            createdAt: savedCreatedAt
        )
    }

    func saveDrawing(
        _ drawingData: Data,
        canvasSize: CGSize,
        authorName: String?,
        createdAt: Date
    ) async throws {
        saveCount += 1
        lastSavedData = drawingData
        lastCanvasSize = canvasSize
        lastAuthorName = authorName
        if let saveError {
            throw saveError
        }
    }

    func clearForPrivacy() async {
        clearCount += 1
    }
}

private final class WidgetCanvasUploadSpy: WidgetCanvasUploading, @unchecked Sendable {
    private(set) var enqueued: [WidgetDrawingUploadPayload] = []

    func enqueueUpload(_ payload: WidgetDrawingUploadPayload) {
        enqueued.append(payload)
    }

    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {
        enqueued.append(payload)
    }
}

private actor SuspendedWidgetCanvasService: WidgetCanvasManaging {
    private var shouldSuspendNextSave = false
    private var suspendedSaveStarted = false
    private var suspendedSaveStartedContinuation: CheckedContinuation<Void, Never>?
    private var suspendedSaveReleaseContinuation: CheckedContinuation<Void, Never>?

    func suspendNextSave() {
        shouldSuspendNextSave = true
        suspendedSaveStarted = false
    }

    func waitForSuspendedSaveToStart() async {
        if suspendedSaveStarted {
            return
        }

        await withCheckedContinuation { continuation in
            suspendedSaveStartedContinuation = continuation
        }
    }

    func releaseSuspendedSave() {
        suspendedSaveReleaseContinuation?.resume()
        suspendedSaveReleaseContinuation = nil
    }

    func loadSavedDrawing() async -> Data? {
        nil
    }

    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? {
        nil
    }

    func saveDrawing(
        _: Data,
        canvasSize _: CGSize,
        authorName _: String?,
        createdAt _: Date
    ) async throws {
        guard shouldSuspendNextSave else {
            return
        }

        shouldSuspendNextSave = false
        suspendedSaveStarted = true
        suspendedSaveStartedContinuation?.resume()
        suspendedSaveStartedContinuation = nil

        await withCheckedContinuation { continuation in
            suspendedSaveReleaseContinuation = continuation
        }
    }

    func clearForPrivacy() async {}
}

private final class WidgetDrawingUndoTestTarget {}

@MainActor
private final class InMemoryWidgetDrawingDraftStore: WidgetDrawingDraftStoring {
    private var drafts: [UUID: Data] = [:]

    func draft(for ownerUserID: UUID) -> Data? {
        drafts[ownerUserID]
    }

    func setDraft(_ data: Data, for ownerUserID: UUID) {
        drafts[ownerUserID] = data
    }

    func clearDraft(for ownerUserID: UUID) {
        drafts[ownerUserID] = nil
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

// swiftlint:enable async_without_await
