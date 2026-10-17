import Foundation
import PostHog
import SwiftUI
import Synchronization

/// Usage statistics and crash reports, sent to Paeonia's PostHog project on EU
/// Cloud. Only Paeonia and PostHog, which stores them for us, can read them, and
/// the data is never sold.
///
/// What leaves the phone: which screens open, the names of the server functions
/// the app calls (never what is sent to them), the app version and device
/// details, and crash stack traces. There are no screen recordings.
///
/// Nothing runs until a paired person has said yes to "Help us improve
/// Paeonia?" (`UsageSharingModel`). Saying no later stops it on this phone at
/// once, and the next launch deletes what PostHog still had queued.
///
/// The key comes from the `PaeoniaPostHogProjectKey` Info.plist entry, which
/// `PAEONIA_POSTHOG_PROJECT_KEY` fills in from the xcconfig files. An empty key
/// leaves PostHog off, and every call here does nothing.
@MainActor
enum PaeoniaAnalytics {
    /// Server functions that are not counted. Some are called so often, or so
    /// mechanically, that counting them says nothing about what people use.
    /// The rest would tell PostHog about reports, a relationship ending, privacy
    /// requests or account deletion.
    nonisolated private static let uncountedFunctions: Set<String> = [
        "access:get_or_create_app_account_token",
        "access:verify_purchase",
        "admin:ban_user",
        "admin:unban_user",
        "analytics:set_usage_sharing",
        "games:create_game_live_ticket",
        "games:set_game_presence",
        "identity:create_privacy_request",
        "identity:delete_account",
        "identity:ensure_current_user",
        "identity:register_user_device",
        "identity:request_account_deletion",
        "location:update_latest_partner_location",
        "media:get_media_signed_url",
        "notifications:register_push_device",
        "notifications:register_widget_push_token",
        "relationship:leave_relationship",
        "relationship:mark_relationship_ended_notice_seen",
        "reports:submit_leave_and_report",
        "widget:create_widget_live_ticket",
        "widget:get_or_create_widget_canvas",
        "widget:register_widget_push_device",
    ]

    /// Set when sharing stops while PostHog holds data. The next launch deletes
    /// PostHog's files before anything starts.
    private static let deletesLocalDataKey = "analytics.deletesLocalDataOnLaunch"

    /// PostHog is running in this process. It cannot be stopped again, only muted.
    private static var isRunning = false
    /// The paired person whose use is counted, if they said yes.
    private static var sharingUserID: String?
    /// Sharing stopped in this run while PostHog held data. Its queue may still
    /// hold events from before, so nothing goes out again until a relaunch has
    /// deleted them.
    private static var isHeldUntilRelaunch = false

    /// Deletes what PostHog left on the phone when sharing stopped in an earlier run.
    static func configure() {
        guard let key = projectKey, UserDefaults.standard.bool(forKey: deletesLocalDataKey) else {
            return
        }
        deleteLocalData(projectKey: key)
        UserDefaults.standard.removeObject(forKey: deletesLocalDataKey)
    }

    /// Counts this person's use from now on, or nobody's when `userID` is nil.
    static func share(as userID: String?) {
        sharingUserID = userID
        apply()
    }

    /// The person said no after a yes, signed out, or is deleting their account.
    /// What PostHog holds for them must never go out: its queue, and crash
    /// reports that carry their identity. Files of a PostHog that has not started
    /// are deleted now. A running one is muted for the rest of the run, and the
    /// next launch deletes its files.
    static func stopSharingAndDeleteQueued() {
        sharingUserID = nil
        guard let key = projectKey else {
            return
        }
        guard isRunning else {
            deleteLocalData(projectKey: key)
            return
        }
        isHeldUntilRelaunch = true
        UserDefaults.standard.set(true, forKey: deletesLocalDataKey)
        apply()
    }

    static func screen(_ name: String) {
        guard isActive else {
            return
        }
        PostHogSDK.shared.screen(name)
    }

    /// Whether this build sends anything at all, so the app can skip the
    /// question in a build without a key.
    static var isAvailable: Bool {
        projectKey != nil
    }

    private static var isActive: Bool {
        isRunning && sharingUserID != nil && !isHeldUntilRelaunch
    }

    private static func apply() {
        guard let key = projectKey else {
            return
        }
        guard let userID = sharingUserID, !isHeldUntilRelaunch else {
            AnalyticsUploadGate.isOpen.withLock { $0 = false }
            if isRunning {
                // Stops new events and crash reports. The gate holds back what
                // PostHog queued earlier.
                PostHogSDK.shared.optOut()
            }
            return
        }
        if !isRunning {
            start(projectKey: key)
        }
        let sdk = PostHogSDK.shared
        sdk.optIn()
        // `identify` keeps an earlier person it was given, so a different
        // person starts from a fresh anonymous visitor first.
        let distinctID = sdk.getDistinctId()
        if distinctID != sdk.getAnonymousId(), distinctID != userID {
            sdk.reset()
        }
        sdk.identify(userID)
        #if DEBUG
        sdk.register(["debug_build": true])
        #endif
        AnalyticsUploadGate.isOpen.withLock { $0 = true }
    }

    private static func start(projectKey: String) {
        let config = PostHogConfig(projectToken: projectKey, host: "https://eu.i.posthog.com")
        // Screens are named by the app (`View.analyticsScreen`), because the
        // automatic names are SwiftUI's internal type names.
        config.captureScreenViews = false
        // PostHog must not hold a push token or read notification text.
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.sessionReplay = false
        // Rage clicks send where on the screen someone tapped.
        config.rageClickConfig.enabled = false
        config.errorTrackingConfig.autoCapture = true

        let session = URLSessionConfiguration.default
        session.protocolClasses = [AnalyticsUploadGate.self] + (session.protocolClasses ?? [])
        config.urlSessionConfiguration = session

        PostHogSDK.shared.setup(config)
        isRunning = true

        PaeoniaConvexClient.setWriteObserver { path in
            guard !uncountedFunctions.contains(path) else {
                return
            }
            PostHogSDK.shared.capture(path)
        }
    }

    /// Deletes PostHog's files: queued events, the stored identity, and the crash
    /// reporter's waiting reports. Only safe while PostHog is not running.
    private static func deleteLocalData(projectKey: String) {
        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let bundleID = Bundle.main.bundleIdentifier {
            try? fileManager.removeItem(at: support.appending(path: bundleID).appending(path: projectKey))
        }
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: caches.appending(path: "com.plausiblelabs.crashreporter.data"))
        }
    }

    private static var projectKey: String? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "PaeoniaPostHogProjectKey") as? String,
            !raw.hasPrefix("$(")
        else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}

// URLProtocol requires `class` members, so the static-over-class rule cannot apply here.
// swiftlint:disable static_over_final_class
/// Fails every PostHog request while nobody shares. PostHog's opt-out stops new
/// events but keeps sending what it queued before, and it has no way to drop
/// that queue. A failed upload stays queued, and the next launch deletes it.
nonisolated final class AnalyticsUploadGate: URLProtocol, @unchecked Sendable {
    static let isOpen = Mutex(false)

    override class func canInit(with _: URLRequest) -> Bool {
        !isOpen.withLock { $0 }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
// swiftlint:enable static_over_final_class

extension View {
    /// Counts a visit to this screen each time it appears.
    func analyticsScreen(_ name: String) -> some View {
        onAppear { PaeoniaAnalytics.screen(name) }
    }
}
