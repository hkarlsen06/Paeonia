import CoreGraphics
import CryptoKit
import Foundation

nonisolated enum WidgetDrawingPublication {
    static func id(drawingData: Data, canvasSide: Double, accessibilityText: String?) -> String {
        id(contentHash: SHA256.hash(data: drawingData).paeoniaHexString,
           canvasSide: canvasSide, accessibilityText: accessibilityText)
    }

    static func id(contentHash: String, canvasSide: Double, accessibilityText: String?) -> String {
        let identity = [contentHash, String(canvasSide.bitPattern), accessibilityText ?? ""].joined(separator: "\0")
        return SHA256.hash(data: Data(identity.utf8)).paeoniaHexString
    }
}

nonisolated struct WidgetPendingUploadSnapshot: Codable, Equatable, Sendable {
    let contentHash: String
    let markedAt: Date
    var lastAttemptAt: Date?
    let canvasSide: Double
    let strokeCount: Int
    let pointCount: Int
    let boundsX: Double
    let boundsY: Double
    let boundsWidth: Double
    let boundsHeight: Double
    var accessibilityText: String?
    /// Where the upload got to, so a retry reuses its IDs. Nil until the
    /// first attempt starts.
    var progress: WidgetUploadProgress?
    /// The inviter's first drawing, made before any partner joined. It belongs to
    /// no couple, so an ended relationship's purge keeps it (`LocalPrivacyPurgeService`).
    let isFirstDay: Bool

    var publicationID: String {
        WidgetDrawingPublication.id(
            contentHash: contentHash, canvasSide: canvasSide, accessibilityText: accessibilityText
        )
    }

    init(
        contentHash: String,
        markedAt: Date,
        lastAttemptAt: Date?,
        payload: WidgetDrawingUploadPayload,
        isFirstDay: Bool = false
    ) {
        self.accessibilityText = payload.accessibilityText
        self.contentHash = contentHash
        self.markedAt = markedAt
        self.lastAttemptAt = lastAttemptAt
        self.isFirstDay = isFirstDay
        canvasSide = Double(payload.canvasSide)
        strokeCount = payload.strokeCount
        pointCount = payload.pointCount
        boundsX = Double(payload.bounds.origin.x)
        boundsY = Double(payload.bounds.origin.y)
        boundsWidth = Double(payload.bounds.width)
        boundsHeight = Double(payload.bounds.height)
    }

    func uploadPayload(with drawingData: Data) -> WidgetDrawingUploadPayload {
        WidgetDrawingUploadPayload(
            drawingData: drawingData,
            canvasSide: CGFloat(canvasSide),
            strokeCount: strokeCount,
            pointCount: pointCount,
            bounds: CGRect(
                x: boundsX,
                y: boundsY,
                width: boundsWidth,
                height: boundsHeight
            ),
            accessibilityText: accessibilityText
        )
    }
}

/// Tracks whether this device has a saved drawing whose upload hasn't been
/// confirmed on the server yet. While something is pending, a sync must not pull
/// a (possibly older) server revision over the newer un-sent local work.
///
/// Keyed by content hash so a later save supersedes an earlier one cleanly, and
/// a confirmed upload only clears the entry if it still matches.
nonisolated final class WidgetPendingUploadStore: @unchecked Sendable {
    nonisolated static let shared = WidgetPendingUploadStore()

    private let defaults: UserDefaults
    private let key: String
    private let retryDelay: TimeInterval

    init(
        defaults: UserDefaults? = nil,
        key: String = "paeonia.widgetCanvas.pendingUpload",
        // Short enough that a reconnect soon after a failed send retries it.
        retryDelay: TimeInterval = 20
    ) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: PaeoniaAppGroup.identifier)
            ?? .standard
        self.key = key
        self.retryDelay = retryDelay
    }

    var hasPending: Bool {
        defaults.data(forKey: key) != nil
    }

    var pendingSnapshot: WidgetPendingUploadSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetPendingUploadSnapshot.self, from: data)
    }

    func markPending(
        _ payload: WidgetDrawingUploadPayload,
        contentHash: String,
        isFirstDay: Bool = false,
        at date: Date = Date()
    ) {
        let snapshot = WidgetPendingUploadSnapshot(
            contentHash: contentHash,
            markedAt: date,
            lastAttemptAt: date,
            payload: payload,
            isFirstDay: isFirstDay
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    func shouldRetry(_ snapshot: WidgetPendingUploadSnapshot, now: Date = Date()) -> Bool {
        guard let lastAttemptAt = snapshot.lastAttemptAt else {
            return true
        }

        return now.timeIntervalSince(lastAttemptAt) >= retryDelay
    }

    func recordAttempt(_ publicationID: String, at date: Date = Date()) {
        guard var snapshot = pendingSnapshot, snapshot.publicationID == publicationID else {
            return
        }

        snapshot.lastAttemptAt = date
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    /// Saves (or, with nil, forgets) the upload progress, but only while the
    /// marker still belongs to this drawing.
    func saveProgress(_ progress: WidgetUploadProgress?, publicationID: String) {
        guard var snapshot = pendingSnapshot, snapshot.publicationID == publicationID else {
            return
        }
        snapshot.progress = progress
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    func clearPending(_ publicationID: String) {
        if pendingSnapshot?.publicationID == publicationID {
            defaults.removeObject(forKey: key)
        }
    }

    /// Puts back `previous` (or clears the marker when there was none), but only
    /// while the marker still belongs to the drawing that replaced it.
    func restore(_ previous: WidgetPendingUploadSnapshot?, replacingPublicationID publicationID: String) {
        guard pendingSnapshot?.publicationID == publicationID else {
            return
        }
        if let previous, let data = try? JSONEncoder().encode(previous) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func clearAll() {
        defaults.removeObject(forKey: key)
    }
}
