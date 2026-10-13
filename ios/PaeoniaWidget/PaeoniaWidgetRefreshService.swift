import CryptoKit
import Foundation
import PencilKit
import UIKit

/// Performs the small authenticated read that keeps the widget current. Clerk
/// reads the session from the keychain access group shared with the host app
/// and refreshes the token. The refresh button and the timeline provider both
/// call it, and it never publishes while the app is purging private content.
enum PaeoniaWidgetRefreshService {
    static let appGroupIdentifier = "group.no.paeonia.app"
    private static let payloadPath = "Widget/current.json"
    // Must match `PaeoniaAppGroup.widgetPreviewsDirectory` exactly. The device
    // file system is case-sensitive, and the app only cleans up (and purges for
    // privacy) the lowercase directory.
    private static let previewsDirectory = "Widget/previews"
    private static let pendingUploadKey = "paeonia.widgetCanvas.pendingUpload"
    // The app bumps this integer before it deletes the widget files, so a
    // refresh that started earlier can tell that it must not publish.
    private static let privacyEpochKey = "paeonia.widget.privacyEpoch"
    // SQLSTATE the backend returns when the user no longer has access.
    private static let accessDeniedCode = "42501"
    private static let downloadTimeout: TimeInterval = 15
    // Same fallback as the app. Strokes live in a canvas of about 300 to 420 points.
    private static let fallbackCanvasSide = 320.0

    @MainActor private static var inFlight: Task<Void, Error>?

    /// Runs one refresh at a time. A caller that arrives while a refresh is
    /// running waits for that refresh instead of starting a second fetch.
    @MainActor
    static func refresh() async throws {
        let task: Task<Void, Error>
        if let inFlight {
            task = inFlight
        } else {
            task = Task { @MainActor in
                defer { inFlight = nil }
                try await performRefresh()
            }
            inFlight = task
        }
        // Waiting on a task ignores cancellation, so pass it on. A caller that
        // gives up (the timeline deadline) then stops the shared fetch quickly.
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @MainActor
    private static func performRefresh() async throws {
        guard PaeoniaClerk.configureIfPossible() else {
            throw RefreshError.missingConfiguration
        }
        guard PaeoniaClerk.currentAccountID() != nil else {
            throw RefreshError.notSignedIn
        }
        let epoch = privacyEpoch()
        let client = try PaeoniaConvexClientProvider.shared.client()
        do {
            guard let remoteDrawing = try await loadRemoteDrawing(client: client),
                  shouldPublish(remoteContentHash: remoteDrawing.contentHash)
            else {
                return
            }
            try publish(remoteDrawing, epoch: epoch)
        } catch let error as PaeoniaConvexError {
            if case let .server(code, _) = error, code == accessDeniedCode {
                removeWidgetFiles()
            }
            throw error
        }
    }

    @MainActor
    private static func loadRemoteDrawing(client: PaeoniaConvexClient) async throws -> RemoteDrawing? {
        let states: FirstRow<CanvasState> = try await client.query("widget:get_widget_canvas")
        guard let state = states.row,
              let revisionID = state.activeRevisionID,
              let mediaAssetID = state.payloadMediaAssetID,
              !isPublished(revisionID: revisionID)
        else {
            return nil
        }

        let signedURL = try await signedPayloadURL(
            client: client,
            mediaAssetID: mediaAssetID
        )
        guard let signedURL else { return nil }
        var request = URLRequest(url: signedURL)
        request.timeoutInterval = downloadTimeout
        let (drawingData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let drawing = try? PKDrawing(data: drawingData)
        else {
            return nil
        }

        return RemoteDrawing(
            drawing: drawing,
            contentHash: contentHash(for: drawingData),
            canvasSide: state.bounds?.canvasSide ?? fallbackCanvasSide,
            revisionID: revisionID,
            authorUserID: state.activeRevisionAuthorUserID,
            createdAt: state.revisionCreatedAt ?? .now
        )
    }

    private static func signedPayloadURL(
        client: PaeoniaConvexClient,
        mediaAssetID: UUID
    ) async throws -> URL? {
        let authorizations: [SignedURLAuthorization] = try await client.mutation(
            "media:get_media_signed_url",
            args: SignedURLRequest(mediaAssetID: mediaAssetID)
        )
        return authorizations.first?.signedURL
    }

    /// True when `Widget/current.json` already shows this server revision and
    /// every family has its preview file, so the download can be skipped.
    private static func isPublished(revisionID: UUID) -> Bool {
        guard let containerURL,
              let data = try? Data(contentsOf: containerURL.appendingPathComponent(payloadPath)),
              let stored = try? JSONDecoder().decode(StoredPayload.self, from: data),
              !stored.isRedacted,
              stored.privacyMode == "normal",
              stored.revisionID.lowercased() == revisionID.uuidString.lowercased()
        else {
            return false
        }

        return PreviewSpec.all.allSatisfy { spec in
            guard let path = stored.previews[spec.family] else { return false }
            return FileManager.default.fileExists(
                atPath: containerURL.appendingPathComponent(path).path
            )
        }
    }

    @MainActor
    private static func publish(_ remoteDrawing: RemoteDrawing, epoch: Int) throws {
        guard remoteDrawing.canvasSide > 0, let containerURL else {
            throw RefreshError.unavailableAppGroup
        }

        // Render in memory first, so the privacy check sits right before the
        // first file write.
        let renderedPreviews = try renderPreviews(remoteDrawing)
        try requireUnchangedPrivacy(since: epoch)
        let previews = try writePreviews(
            renderedPreviews,
            revisionID: remoteDrawing.revisionID,
            in: containerURL
        )
        do {
            try writePayload(for: remoteDrawing, previews: previews, epoch: epoch, in: containerURL)
        } catch {
            removePreviews(previews, in: containerURL)
            throw error
        }
    }

    @MainActor
    private static func renderPreviews(
        _ remoteDrawing: RemoteDrawing
    ) throws -> [(spec: PreviewSpec, pngData: Data)] {
        let canvasSide = CGFloat(remoteDrawing.canvasSide)
        return try PreviewSpec.all.map { spec in
            let scale = max(1, CGFloat(spec.pixelWidth) / canvasSide)
            var image: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = remoteDrawing.drawing.image(
                    from: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide),
                    scale: scale
                )
            }
            guard let pngData = image?.pngData() else {
                throw RefreshError.renderFailed
            }
            return (spec: spec, pngData: pngData)
        }
    }

    /// Writes every preview file and returns the payload paths by family. A
    /// failed write removes the files already written.
    private static func writePreviews(
        _ renderedPreviews: [(spec: PreviewSpec, pngData: Data)],
        revisionID: UUID,
        in containerURL: URL
    ) throws -> [String: String] {
        let previewsURL = containerURL.appendingPathComponent(
            previewsDirectory,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: previewsURL,
            withIntermediateDirectories: true
        )

        var previews: [String: String] = [:]
        do {
            for (spec, pngData) in renderedPreviews {
                let fileName = "\(spec.family)-\(revisionID.uuidString.lowercased()).png"
                try pngData.write(
                    to: previewsURL.appendingPathComponent(fileName),
                    options: .atomic
                )
                previews[spec.family] = "\(previewsDirectory)/\(fileName)"
            }
        } catch {
            removePreviews(previews, in: containerURL)
            throw error
        }
        return previews
    }

    /// Writes `Widget/current.json`, the file that makes the new drawing visible.
    @MainActor
    private static func writePayload(
        for remoteDrawing: RemoteDrawing,
        previews: [String: String],
        epoch: Int,
        in containerURL: URL
    ) throws {
        let authorName = WidgetIdentity.load().authorName(for: remoteDrawing.authorUserID)
        let payload = CurrentPayload(
            revisionID: remoteDrawing.revisionID.uuidString.lowercased(),
            authorName: authorName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: remoteDrawing.createdAt,
            renderedAt: .now,
            contentHash: remoteDrawing.contentHash,
            previews: previews,
            canvasSide: remoteDrawing.canvasSide
        )
        let payloadData = try CurrentPayload.encoder.encode(payload)

        // Downloading and rendering take time. The user may have signed out, the
        // app may have purged the widget, or the app may have saved a newer local
        // drawing. Check again right before the write.
        try requireUnchangedPrivacy(since: epoch)
        guard shouldPublish(remoteContentHash: remoteDrawing.contentHash) else {
            throw RefreshError.superseded
        }
        try payloadData.write(
            to: containerURL.appendingPathComponent(payloadPath),
            options: .atomic
        )
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static func privacyEpoch() -> Int {
        UserDefaults(suiteName: appGroupIdentifier)?.integer(forKey: privacyEpochKey) ?? 0
    }

    @MainActor
    private static func requireUnchangedPrivacy(since epoch: Int) throws {
        guard privacyEpoch() == epoch, PaeoniaClerk.currentAccountID() != nil else {
            throw RefreshError.privacyChanged
        }
    }

    private static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

// Pending-upload and cleanup helpers.
extension PaeoniaWidgetRefreshService {
    private static func removePreviews(_ previews: [String: String], in containerURL: URL) {
        for path in previews.values {
            try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(path))
        }
    }

    /// Removes the same files as the app's privacy hide, so a partner's drawing
    /// does not stay on the Home Screen after the relationship or access ended.
    private static func removeWidgetFiles() {
        guard let containerURL else { return }
        try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(payloadPath))
        try? FileManager.default.removeItem(
            at: containerURL.appendingPathComponent(previewsDirectory, isDirectory: true)
        )
    }

    private static func shouldPublish(remoteContentHash: String) -> Bool {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        if let pendingData = defaults?.data(forKey: pendingUploadKey) {
            guard let pending = try? JSONDecoder().decode(PendingUpload.self, from: pendingData),
                  remoteContentHash == "sha256-\(pending.contentHash)"
            else {
                return false
            }

            // Matching server bytes confirm the host app's pending upload even
            // when the interactive widget performed the first successful read.
            clearPendingUploadIfMatching(pending.contentHash, defaults: defaults)
            return true
        }

        // With no unsent local save, the server read is authoritative. Avoid
        // client/server timestamp comparisons: clock skew previously made a
        // real partner revision look older indefinitely.
        return true
    }

    private static func clearPendingUploadIfMatching(
        _ contentHash: String,
        defaults: UserDefaults?
    ) {
        if let pendingData = defaults?.data(forKey: pendingUploadKey),
           let pending = try? JSONDecoder().decode(PendingUpload.self, from: pendingData),
           pending.contentHash == contentHash {
            defaults?.removeObject(forKey: pendingUploadKey)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
