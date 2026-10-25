import Foundation

/// The drawing screen's uploader before sign-in. There is no account to send to, so a
/// send only marks the drawing as the first-day drawing that waits, in the welcome
/// flow's own marker (`WelcomeDrawingStorage`). At sign-in `WelcomeFlowModel` moves it
/// to the marker `FirstDayDrawingUploadService` reads, and the invite screen sends the
/// drawing to the first day draft.
///
/// To the drawing screen a send is done, and nothing is pending. Its waiting state says
/// the drawing goes out once the phone is online, which is not true before sign-in.
actor WelcomeDrawingUploader: WidgetCanvasUploading {
    private let pendingStore: WidgetPendingUploadStore

    init(pendingStore: WidgetPendingUploadStore = WelcomeDrawingStorage.pendingUploads) {
        self.pendingStore = pendingStore
    }

    var hasPendingUpload: Bool {
        false
    }

    func markPending(_ payload: WidgetDrawingUploadPayload) -> WidgetPendingUploadSnapshot? {
        let previous = pendingStore.pendingSnapshot
        pendingStore.markPending(
            payload,
            contentHash: WidgetCanvasUploadService.sha256Hex(of: payload.drawingData),
            isFirstDay: true
        )
        return previous
    }

    func restorePending(_ previous: WidgetPendingUploadSnapshot?, replacing payload: WidgetDrawingUploadPayload) {
        pendingStore.restore(
            previous,
            replacingContentHash: WidgetCanvasUploadService.sha256Hex(of: payload.drawingData)
        )
    }

    func send(_: WidgetDrawingUploadPayload) -> WidgetDrawingDelivery {
        .delivered
    }

    func uploadPending(_: WidgetDrawingUploadPayload) throws {
        throw NoAccount()
    }

    nonisolated private struct NoAccount: Error {}
}
