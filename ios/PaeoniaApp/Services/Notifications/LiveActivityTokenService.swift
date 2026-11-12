import ActivityKit
import Foundation
#if DEBUG
import OSLog
#endif

/// Hands the server the tokens ActivityKit gives this phone for the partner's game activity: the
/// token that lets the server start one, and each running activity's own token for its updates
/// and its end. iOS can change either at any time, so it follows both while someone is signed in,
/// from the app's launch on. A push that starts an activity launches a closed app in the
/// background and hands it the activity's token then, so this cannot wait for a screen.
final class LiveActivityTokenService {
    static let shared = LiveActivityTokenService(
        registry: ConvexLiveActivityTokenServer.makeDefault().map {
            LiveActivityInstallRegistry(store: KeychainLiveActivityInstallStore(), server: $0)
        }
    )

    private let registry: LiveActivityInstallRegistry?
    private var followedAccountID: String?
    private var tasks: [Task<Void, Never>] = []
    /// One per activity this session saw. It stops following the activity's token once the activity ended.
    private var activityTasks: [String: Task<Void, Never>] = [:]
    /// Sends the ends of past sign-ins until the server has them all, whatever else happens.
    private var endsTask: Task<Void, Never>?

    #if DEBUG
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app", category: "LiveActivity")
    #endif

    init(registry: LiveActivityInstallRegistry?) {
        self.registry = registry
    }

    /// Call at every launch of the real app, including a launch in the background.
    func resumeAfterLaunch() {
        sendEnds()
        Task {
            resume(
                accountID: await PaeoniaClerk.loadedAccountID(timeout: .seconds(8)),
                clerkHasLoaded: PaeoniaClerk.hasLoaded,
                storedSessionIsReadable: ClerkKeychainState.current() != .locked
            )
        }
    }

    /// Follows the tokens of `accountID`, the account Clerk loaded at launch. When Clerk loaded and
    /// found nobody signed in, no activity should show, and an install left by a session that ended
    /// while the app was closed ends now. Before the first unlock after a restart Clerk cannot read
    /// the saved sign-in and only looks signed out, so nothing ends then.
    func resume(accountID: String?, clerkHasLoaded: Bool, storedSessionIsReadable: Bool) {
        if let accountID {
            start(accountID: accountID)
        } else if clerkHasLoaded, storedSessionIsReadable {
            endSession()
        }
    }

    /// Follows the tokens for the signed-in account. Safe to call on every activation.
    func start() {
        guard let accountID = PaeoniaClerk.currentAccountID() else {
            return
        }
        start(accountID: accountID)
    }

    /// The app came to the front. Without a signed-in account nothing may show. Otherwise a stale
    /// activity no longer says anything true about the partner, so it ends, and the server hears
    /// of it so the partner's next game can start a fresh one.
    func foregrounded(signedIn: Bool) async {
        guard signedIn else {
            endSession()
            return
        }
        report(ended: await GameLiveActivityController.endStaleActivities())
        sendEnds()
    }

    /// The person opened `kind`, so an activity that invites them to it has done its job.
    func gameOpened(_ kind: GameKind) async {
        report(ended: await GameLiveActivityController.endActivities(for: kind))
    }

    /// The sign-in ended on this phone, in any way: a sign-out, a session that ended elsewhere
    /// or expired, a deleted account, or another account that signed in. Stops following,
    /// ends the activities on screen, and ends this sign-in's install on the server.
    func endSession() {
        (tasks + activityTasks.values).forEach { $0.cancel() }
        tasks = []
        activityTasks = [:]
        followedAccountID = nil
        do {
            try registry?.endInstall()
        } catch {
            log("Ending the Live Activity install failed: \(error)")
        }
        Task { await GameLiveActivityController.endAll() }
        sendEnds()
    }

    private func start(accountID: String) {
        guard followedAccountID != accountID, let registry else {
            return
        }
        if let installAccountID = try? registry.accountID, installAccountID != accountID {
            endSession()
        }
        followedAccountID = accountID
        tasks.append(Task {
            // A new sign-in needs the token too, not only later changes of it.
            if let token = Activity<GameLiveActivityAttributes>.pushToStartToken {
                await register(token, of: nil, for: accountID)
            }
            for await token in Activity<GameLiveActivityAttributes>.pushToStartTokenUpdates {
                await register(token, of: nil, for: accountID)
            }
        })
        tasks.append(Task {
            for await activity in Activity<GameLiveActivityAttributes>.activityUpdates {
                follow(activity, for: accountID)
            }
        })
        for activity in Activity<GameLiveActivityAttributes>.activities {
            follow(activity, for: accountID)
        }
    }

    private func follow(_ activity: Activity<GameLiveActivityAttributes>, for accountID: String) {
        let id = activity.id
        guard activityTasks[id] == nil else {
            return
        }
        let activityID = activity.attributes.activityID
        let tokens = Task {
            if let token = activity.pushToken {
                await register(token, of: (id, activityID), for: accountID)
            }
            for await token in activity.pushTokenUpdates {
                await register(token, of: (id, activityID), for: accountID)
            }
        }
        activityTasks[id] = Task {
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                break
            }
            tokens.cancel()
        }
    }

    /// Registers the push-to-start token, or the token of an activity, and tries again with a
    /// growing wait until it goes through. An activity the server says has ended ends here too,
    /// since no push will reach it.
    private func register(
        _ token: Data,
        of activity: (id: String, activityID: String)?,
        for accountID: String
    ) async {
        guard let registry else {
            return
        }
        var wait = Duration.seconds(2)
        while !Task.isCancelled {
            do {
                let result = try await registry.register(
                    activity == nil ? .start : .update,
                    token: token.paeoniaHexString,
                    activityID: activity?.activityID,
                    for: accountID
                )
                if let activity, result == .ended {
                    await GameLiveActivityController.end(activityWithID: activity.id)
                }
                return
            } catch where Self.isRefusal(error) {
                // A session the server no longer accepts or a token it cannot use. Sending it again
                // cannot help, and the app's session checks sign out a session that really ended.
                log("Live Activity token refused: \(error)")
                return
            } catch {
                log("Live Activity token registration failed, trying again in \(wait): \(error)")
                try? await Task.sleep(for: wait)
                wait = min(wait * 2, .seconds(300))
            }
        }
    }

    /// Tells the server about activities this phone ended on its own. A lost report costs little,
    /// because the server ends the activity once the partner leaves.
    private func report(ended activityIDs: [String]) {
        guard let registry, let accountID = followedAccountID, !activityIDs.isEmpty else {
            return
        }
        Task {
            for activityID in activityIDs {
                for attempt in 1 ... 3 {
                    do {
                        try await registry.endActivity(activityID, for: accountID)
                        break
                    } catch {
                        log("Reporting an ended Live Activity failed: \(error)")
                        if Self.isRefusal(error) { break }
                        try? await Task.sleep(for: .seconds(attempt * 5))
                    }
                }
            }
        }
    }

    /// Sends pending install ends with a growing wait after a failure, and once more when an end's
    /// second send is due. A new call starts over at once.
    private func sendEnds() {
        guard let registry else {
            return
        }
        endsTask?.cancel()
        endsTask = Task {
            var wait = Duration.seconds(2)
            while !Task.isCancelled {
                do {
                    guard let next = try await registry.sendEnds() else {
                        return
                    }
                    wait = .seconds(2)
                    try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                } catch {
                    log("Ending an old Live Activity install failed, trying again in \(wait): \(error)")
                    try? await Task.sleep(for: wait)
                    wait = min(wait * 2, .seconds(300))
                }
            }
        }
    }

    /// The server refused the request itself, so sending it again cannot help.
    private static func isRefusal(_ error: any Error) -> Bool {
        guard case let .server(code, _) = error as? PaeoniaConvexError else {
            return false
        }
        return code == PaeoniaConvexError.accessDeniedCode || code == "23514" || code == "22P02"
    }

    private func log(_ message: String) {
        #if DEBUG
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
