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

    init(
        contentHash: String,
        markedAt: Date,
        lastAttemptAt: Date?,
        payload: WidgetDrawingUploadPayload
    ) {
        self.contentHash = contentHash
        self.markedAt = markedAt
        self.lastAttemptAt = lastAttemptAt
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
    private let key = "paeonia.widgetCanvas.pendingUpload"
    private let legacyHashKey = "paeonia.widgetCanvas.pendingUploadHash"
    private let retryDelay: TimeInterval

    init(
        defaults: UserDefaults? = nil,
        retryDelay: TimeInterval = 60
    ) {
        let resolvedDefaults = defaults
            ?? UserDefaults(suiteName: PaeoniaAppGroup.identifier)
            ?? .standard
        self.defaults = resolvedDefaults
        self.retryDelay = retryDelay

        // Older builds kept this guard in app-only defaults. Move it once so
        // the widget extension can protect the same pending local save during
        // an interactive refresh.
        if defaults == nil, resolvedDefaults !== UserDefaults.standard {
            if resolvedDefaults.data(forKey: key) == nil,
               let legacyData = UserDefaults.standard.data(forKey: key) {
                resolvedDefaults.set(legacyData, forKey: key)
            }
            if resolvedDefaults.string(forKey: legacyHashKey) == nil,
               let legacyHash = UserDefaults.standard.string(forKey: legacyHashKey) {
                resolvedDefaults.set(legacyHash, forKey: legacyHashKey)
            }
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: legacyHashKey)
        }
    }

    var hasPending: Bool {
        defaults.data(forKey: key) != nil || defaults.string(forKey: legacyHashKey) != nil
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
        at date: Date = Date()
    ) {
        let snapshot = WidgetPendingUploadSnapshot(
            contentHash: contentHash,
            markedAt: date,
            lastAttemptAt: date,
            payload: payload
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
            defaults.removeObject(forKey: legacyHashKey)
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

    func clearPending(_ contentHash: String) {
        if pendingSnapshot?.contentHash == contentHash {
            defaults.removeObject(forKey: key)
        }
        if defaults.string(forKey: legacyHashKey) == contentHash {
            defaults.removeObject(forKey: legacyHashKey)
        }
    }

    func clearAll() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyHashKey)
    }
}
