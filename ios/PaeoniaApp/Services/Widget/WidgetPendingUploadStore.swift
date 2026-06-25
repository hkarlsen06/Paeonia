import Foundation

/// Tracks whether this device has a saved drawing whose upload hasn't been
/// confirmed on the server yet. While something is pending, a sync must not pull
/// a (possibly older) server revision over the newer un-sent local work.
///
/// Keyed by content hash so a later save supersedes an earlier one cleanly, and
/// a confirmed upload only clears the entry if it still matches.
nonisolated final class WidgetPendingUploadStore: @unchecked Sendable {
    nonisolated static let shared = WidgetPendingUploadStore()

    private let defaults: UserDefaults
    private let key = "paeonia.widgetCanvas.pendingUploadHash"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasPending: Bool {
        defaults.string(forKey: key) != nil
    }

    func markPending(_ contentHash: String) {
        defaults.set(contentHash, forKey: key)
    }

    func clearPending(_ contentHash: String) {
        if defaults.string(forKey: key) == contentHash {
            defaults.removeObject(forKey: key)
        }
    }
}
