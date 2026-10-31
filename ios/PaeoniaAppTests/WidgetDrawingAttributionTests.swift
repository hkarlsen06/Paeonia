import PencilKit
import Testing
@testable import PaeoniaApp

/// Edited-state detection for the drawing canvas.
@MainActor
struct WidgetDrawingAttributionTests {
    @Test(arguments: [false, true])
    func differentRemoteStrokesKeepTheUnsentDrawingsDescription(partnerIsDrawing: Bool) async {
        let service = WidgetCanvasServiceSpy()
        let first = makeNonEmptyDrawing(seed: 20)
        service.savedDrawingData = first.dataRepresentation()
        service.savedAccessibilityText = "Our house"
        let drafts = InMemoryWidgetDrawingDraftStore()
        let owner = UUID()
        let couple = UUID()
        let connection = WidgetLiveConnection(coupleID: couple)
        var presence = WidgetLivePresence()
        presence.welcome(id: "me", peers: 1)
        let live = WidgetLiveDrawing(connection: connection, presence: presence)
        if partnerIsDrawing {
            connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: "drawing"))
        }
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: owner, coupleID: couple, service: service,
            uploader: WidgetCanvasUploadSpy(), draftStore: drafts, live: live
        )
        await viewModel.loadSavedDrawingIfNeeded()
        let unsent = PKDrawing(strokes: first.strokes + makeNonEmptyDrawing(seed: 48).strokes)
        viewModel.updateDrawing(unsent)
        service.savedDrawingData = makeNonEmptyDrawing(seed: 92).dataRepresentation()
        service.savedAccessibilityText = "A flower"
        await viewModel.reloadSavedDrawingFromSyncIfSafe()
        if partnerIsDrawing {
            #expect(viewModel.drawing.paeoniaContentSignature == unsent.paeoniaContentSignature)
            #expect(viewModel.accessibilityText == "Our house")
        } else {
            let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple, slot: .setAside)
            #expect(drafts.description(for: key) == "Our house")
            #expect(viewModel.accessibilityText == "A flower")
        }
    }

    @Test func descriptionOnlyRemoteUpdatesDoNotRelabelUnsentStrokes() async {
        let service = WidgetCanvasServiceSpy()
        let first = makeNonEmptyDrawing(seed: 20)
        service.savedDrawingData = first.dataRepresentation()
        service.savedAccessibilityText = "Our house"
        let viewModel = WidgetDrawingViewModel(service: service, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()
        viewModel.updateDrawing(PKDrawing(strokes: first.strokes + makeNonEmptyDrawing(seed: 48).strokes))
        service.savedAccessibilityText = "Our house with a red roof"
        await viewModel.reloadSavedDrawingFromSyncIfSafe()
        #expect(viewModel.accessibilityText == "Our house")
    }

    @Test func aSavedLiveDrawingAdoptsItsDescriptionWhenTheStrokesAlreadyMatch() async {
        let service = WidgetCanvasServiceSpy()
        let first = makeNonEmptyDrawing(seed: 20)
        service.savedDrawingData = first.dataRepresentation()
        service.savedAccessibilityText = "A circle"
        let viewModel = WidgetDrawingViewModel(service: service, uploader: WidgetCanvasUploadSpy())
        await viewModel.loadSavedDrawingIfNeeded()
        let live = PKDrawing(strokes: first.strokes + makeNonEmptyDrawing(seed: 48).strokes)
        viewModel.drawing = live
        service.savedDrawingData = live.dataRepresentation()
        service.savedAccessibilityText = "Two circles"
        await viewModel.reloadSavedDrawingFromSyncIfSafe()
        #expect(viewModel.accessibilityText == "Two circles")
        #expect(!viewModel.hasUnsavedEdits)
    }

    @Test func aSavedLiveDrawingKeepsAnUnsentDescriptionOnDisk() async {
        let service = WidgetCanvasServiceSpy()
        let first = makeNonEmptyDrawing(seed: 20)
        service.savedDrawingData = first.dataRepresentation()
        service.savedAccessibilityText = "A circle"
        let drafts = InMemoryWidgetDrawingDraftStore()
        let owner = UUID()
        let couple = UUID()
        let viewModel = WidgetDrawingViewModel(
            ownerUserID: owner, coupleID: couple, service: service,
            uploader: WidgetCanvasUploadSpy(), draftStore: drafts
        )
        await viewModel.loadSavedDrawingIfNeeded()
        let live = PKDrawing(strokes: first.strokes + makeNonEmptyDrawing(seed: 48).strokes)
        viewModel.drawing = live
        viewModel.updateAccessibilityText("My description still needs work")
        service.savedDrawingData = live.dataRepresentation()
        service.savedAccessibilityText = "Two circles"
        await viewModel.reloadSavedDrawingFromSyncIfSafe()
        let key = WidgetDrawingDraftKey(ownerUserID: owner, coupleID: couple)
        #expect(viewModel.accessibilityText == "My description still needs work")
        #expect(viewModel.hasUnsavedEdits)
        #expect(drafts.description(for: key) == "My description still needs work")
        #expect(drafts.draft(for: key) != nil)
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
}
