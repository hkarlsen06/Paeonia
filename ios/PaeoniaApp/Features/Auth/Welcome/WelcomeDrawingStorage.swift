import Foundation

/// Where the first drawing waits before sign-in: a canvas and a "not sent yet" marker
/// of its own, in the app's own files and defaults. The widget's canvas
/// (`WidgetCanvasService.shared`) and marker (`WidgetPendingUploadStore.shared`) may
/// still hold another account's drawing then. The welcome canvas never shows it, and
/// clearing that account's data when someone else signs in never reaches the first
/// drawing. `WelcomeFlowModel.sessionStarted` moves it to the widget's canvas and
/// marker after that clearing, so it belongs to whoever signed in.
nonisolated enum WelcomeDrawingStorage {
    static let pendingUploadKey = "paeonia.welcome.drawingPendingUpload"

    static let canvas: WidgetCanvasService = {
        let directory = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WelcomeDrawing", isDirectory: true)
        // The widget previews and their payload go in this folder instead of the App
        // Group, so nothing on the Home Screen changes before sign-in.
        return WidgetCanvasService(
            appGroupContainerURL: directory,
            canonicalDrawingURL: directory?.appendingPathComponent("current.pkdrawing"),
            reloader: NoWidgetReload(),
            sharedDefaults: nil
        )
    }()

    static let pendingUploads = WidgetPendingUploadStore(defaults: .standard, key: pendingUploadKey)

    private struct NoWidgetReload: WidgetTimelineReloading {
        // swiftlint:disable:next async_without_await
        func reloadWidget() async {}
    }
}
