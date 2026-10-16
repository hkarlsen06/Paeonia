// The app target compiles every file in the widget folder that its project
// exception list does not name. Only the extension fetches this state.
#if WIDGET_EXTENSION
import Foundation

/// Fetches `widget:get_lock_screen_state` and keeps the answer in the App
/// Group, so every Lock Screen widget reads one file. It uses the same Clerk
/// session and Convex client as `PaeoniaWidgetRefreshService`.
enum LockScreenStateService {
    private static let appGroupIdentifier = "group.no.paeonia.app"
    // Must match `PaeoniaAppGroup`. The app bumps this before it deletes widget files.
    private static let privacyEpochKey = "paeonia.widget.privacyEpoch"

    /// The fetch that is running, and when it started.
    private struct InFlight {
        let id: UUID
        let startedAt: Date
        let task: Task<Void, Error>
    }

    @MainActor private static var inFlight: InFlight?

    /// Reads the cache. Nil when there is no cache, or it cannot be read.
    static func loadCache() -> LockScreenCache? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? LockScreenCache.decode(data)
    }

    /// Fetches a new snapshot. One push reloads every Lock Screen widget at
    /// once, so a reload that arrives while a fetch runs waits for that fetch.
    /// The exception is a fetch that started before the app's last write
    /// (`invalidatedAt`). Its answer may be old, so the reload waits for it and
    /// then fetches again.
    @MainActor
    static func refresh() async throws {
        let invalidatedAt = UserDefaults(suiteName: appGroupIdentifier)?
            .object(forKey: LockScreenCache.invalidatedAtKey) as? Date
        let task: Task<Void, Error>
        if let inFlight, invalidatedAt.map({ inFlight.startedAt > $0 }) ?? true {
            task = inFlight.task
        } else {
            let previous = inFlight?.task
            let id = UUID()
            task = Task { @MainActor in
                defer { if inFlight?.id == id { inFlight = nil } }
                // Let the older fetch finish first, so it can't overwrite this answer.
                _ = try? await previous?.value
                try await performRefresh()
            }
            inFlight = InFlight(id: id, startedAt: .now, task: task)
        }
        // Waiting on a task ignores cancellation, so pass it on. A caller that
        // gives up at the timeline deadline then stops the shared fetch.
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Runs `refresh()` but stops waiting after `deadline`. A timeout or an
    /// error leaves the cache as it is.
    static func refreshWithinDeadline(_ deadline: Duration = .seconds(10)) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await refresh() }
            group.addTask { try? await Task.sleep(for: deadline) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    @MainActor
    private static func performRefresh() async throws {
        typealias RefreshError = PaeoniaWidgetRefreshService.RefreshError
        guard PaeoniaClerk.configureIfPossible() else {
            throw RefreshError.missingConfiguration
        }
        guard PaeoniaClerk.currentAccountID() != nil else {
            // Nobody is signed in, so nothing private may stay on the Lock Screen.
            removeCache()
            throw RefreshError.notSignedIn
        }
        let epoch = privacyEpoch()
        let client = try PaeoniaConvexClientProvider.shared.client()
        do {
            let snapshot: LockScreenSnapshot? = try await client.query(
                "widget:get_lock_screen_state",
                args: LockScreenStateRequest(now: .now)
            )
            // The user may have signed out or the app may have purged the widget
            // while the request was running.
            guard privacyEpoch() == epoch, PaeoniaClerk.currentAccountID() != nil else {
                throw RefreshError.privacyChanged
            }
            if let snapshot {
                try write(LockScreenCache(fetchedAt: .now, snapshot: snapshot))
            } else {
                // No active couple.
                removeCache()
            }
        } catch let error as PaeoniaConvexError {
            if case let .server(code, _) = error, code == PaeoniaConvexError.accessDeniedCode {
                removeCache()
            }
            throw error
        }
        // Any other error, such as a lost connection, keeps the cache.
    }

    private static func write(_ cache: LockScreenCache) throws {
        guard let url = cacheURL else {
            throw PaeoniaWidgetRefreshService.RefreshError.unavailableAppGroup
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try cache.encoded().write(to: url, options: .atomic)
    }

    private static func removeCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(LockScreenCache.relativePath)
    }

    private static func privacyEpoch() -> Int {
        UserDefaults(suiteName: appGroupIdentifier)?.integer(forKey: privacyEpochKey) ?? 0
    }
}
#endif
