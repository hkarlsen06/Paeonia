import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

/// Saving a drawing: what reaches the local copy, the upload queue and the draft.
@MainActor
struct WidgetDrawingViewModelTests {
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

    @Test func failedSaveDoesNotEnqueueUpload() async {
        let serviceSpy = WidgetCanvasServiceSpy()
        serviceSpy.saveError = WidgetDrawingTestError.failed
        let uploadSpy = WidgetCanvasUploadSpy()
        let viewModel = WidgetDrawingViewModel(service: serviceSpy, uploader: uploadSpy)
        viewModel.drawing = makeNonEmptyDrawing()

        await viewModel.save()

        #expect(uploadSpy.enqueued.isEmpty)
    }
}
