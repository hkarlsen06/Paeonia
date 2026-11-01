import CoreGraphics
import Foundation

nonisolated struct WidgetPendingUploadSnapshot: Codable, Equatable, Sendable {
    let publicationID: UUID
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

    init(
        contentHash: String,
        markedAt: Date,
        lastAttemptAt: Date?,
        payload: WidgetDrawingUploadPayload,
        isFirstDay: Bool = false
    ) {
        publicationID = payload.publicationID
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
            accessibilityText: accessibilityText,
            publicationID: publicationID
        )
    }
}

/// Tracks whether this device has a saved drawing whose upload hasn't been
/// confirmed on the server yet. While something is pending, a sync must not pull
/// a (possibly older) server revision over the newer un-sent local work.
///
/// Each send has its own identity, even when its bytes and description match an
/// earlier send. A late callback can change only the marker for its own send.
nonisolated final class WidgetPendingUploadStore: @unchecked Sendable {
    nonisolated static let shared = WidgetPendingUploadStore()
    /// Several service actors and store instances share the same defaults key.
    /// Keep their read, identity check and write in one critical section.
    private static let lock = NSLock()

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
        Self.lock.withLock { defaults.data(forKey: key) != nil }
    }

    var pendingSnapshot: WidgetPendingUploadSnapshot? {
        Self.lock.withLock { readSnapshotUnlocked() }
    }

    private func readSnapshotUnlocked() -> WidgetPendingUploadSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetPendingUploadSnapshot.self, from: data)
    }

    @discardableResult
    func markPending(
        _ payload: WidgetDrawingUploadPayload,
        contentHash: String,
        isFirstDay: Bool = false,
        at date: Date = Date()
    ) -> WidgetPendingUploadSnapshot? {
        let snapshot = WidgetPendingUploadSnapshot(
            contentHash: contentHash,
            markedAt: date,
            lastAttemptAt: date,
            payload: payload,
            isFirstDay: isFirstDay
        )
        return Self.lock.withLock {
            let previous = readSnapshotUnlocked()
            // Re-marking a retry must retain its operations and retry clock.
            guard previous?.publicationID != payload.publicationID else { return previous }
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: key)
            }
            return previous
        }
    }

    func shouldRetry(_ snapshot: WidgetPendingUploadSnapshot, now: Date = Date()) -> Bool {
        guard let lastAttemptAt = snapshot.lastAttemptAt else {
            return true
        }

        return now.timeIntervalSince(lastAttemptAt) >= retryDelay
    }

    func recordAttempt(_ publicationID: UUID, at date: Date = Date()) {
        Self.lock.withLock {
            guard var snapshot = readSnapshotUnlocked(), snapshot.publicationID == publicationID else { return }
            snapshot.lastAttemptAt = date
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: key)
            }
        }
    }

    /// Saves (or, with nil, forgets) the upload progress, but only while the
    /// marker still belongs to this drawing.
    func saveProgress(_ progress: WidgetUploadProgress?, publicationID: UUID) {
        Self.lock.withLock {
            guard var snapshot = readSnapshotUnlocked(), snapshot.publicationID == publicationID else { return }
            snapshot.progress = progress
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: key)
            }
        }
    }

    func clearPending(_ publicationID: UUID) {
        Self.lock.withLock {
            if readSnapshotUnlocked()?.publicationID == publicationID {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Puts back `previous` (or clears the marker when there was none), but only
    /// while the marker still belongs to the drawing that replaced it.
    func restore(_ previous: WidgetPendingUploadSnapshot?, replacingPublicationID publicationID: UUID) {
        Self.lock.withLock {
            guard readSnapshotUnlocked()?.publicationID == publicationID else { return }
            if let previous, let data = try? JSONEncoder().encode(previous) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func clearAll() {
        Self.lock.withLock { defaults.removeObject(forKey: key) }
    }
}
