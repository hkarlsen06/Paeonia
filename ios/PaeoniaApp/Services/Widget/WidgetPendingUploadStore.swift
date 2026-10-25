import CoreGraphics
import Foundation

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
    /// Where the upload got to, so a retry reuses its IDs. Nil until the
    /// first attempt starts.
    var progress: WidgetUploadProgress?
    /// The inviter's first drawing, made before any partner joined. It belongs to
    /// no couple, so an ended relationship's purge keeps it (`LocalPrivacyPurgeService`).
    let isFirstDay: Bool

    init(
        contentHash: String,
        markedAt: Date,
        lastAttemptAt: Date?,
        payload: WidgetDrawingUploadPayload,
        isFirstDay: Bool = false
    ) {
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
            )
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

    func recordAttempt(_ contentHash: String, at date: Date = Date()) {
        guard var snapshot = pendingSnapshot, snapshot.contentHash == contentHash else {
            return
        }

        snapshot.lastAttemptAt = date
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    /// Saves (or, with nil, forgets) the upload progress, but only while the
    /// marker still belongs to this drawing.
    func saveProgress(_ progress: WidgetUploadProgress?, contentHash: String) {
        guard var snapshot = pendingSnapshot, snapshot.contentHash == contentHash else {
            return
        }
        snapshot.progress = progress
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    func clearPending(_ contentHash: String) {
        if pendingSnapshot?.contentHash == contentHash {
            defaults.removeObject(forKey: key)
        }
    }

    /// Puts back `previous` (or clears the marker when there was none), but only
    /// while the marker still belongs to the drawing that replaced it.
    func restore(_ previous: WidgetPendingUploadSnapshot?, replacingContentHash contentHash: String) {
        guard pendingSnapshot?.contentHash == contentHash else {
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
