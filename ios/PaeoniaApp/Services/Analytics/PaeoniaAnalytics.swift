import Foundation
import PostHog
import SwiftUI
import Synchronization

/// Usage statistics, session replays and crash reports, sent to Paeonia's PostHog
/// project on EU Cloud. Only Paeonia reads them, and the data is never sold.
///
/// What leaves the phone: which screens open, the names of the server functions
/// the app calls (never what is sent to them), the app version and device model,
/// crash stack traces, and replays. A replay hides every text and every image,
/// and `hiddenFromReplaysAccessibilityToken` hides drawings, the camera and the
/// 3D board. Replays record no touches, and rage clicks are off, because touch
/// points on a canvas trace the drawing. Turning off "Share usage statistics"
/// (`isSharingEnabled`) stops all of it on this phone.
///
/// The key comes from the `PaeoniaPostHogProjectKey` Info.plist entry, which
/// `PAEONIA_POSTHOG_PROJECT_KEY` fills in from the xcconfig files. An empty key
/// leaves PostHog off, and every call here does nothing.
@MainActor
enum PaeoniaAnalytics {
    /// Server functions called so often, or so mechanically, that counting them
    /// says nothing about what people use.
    nonisolated private static let uncountedFunctions: Set<String> = [
        "access:get_or_create_app_account_token",
        "access:verify_purchase",
        "games:create_game_live_ticket",
        "games:set_game_presence",
        "identity:ensure_current_user",
        "identity:register_user_device",
        "location:update_latest_partner_location",
        "media:get_media_signed_url",
        "notifications:register_push_device",
        "notifications:register_widget_push_token",
        "widget:create_widget_live_ticket",
        "widget:get_or_create_widget_canvas",
        "widget:register_widget_push_device",
    ]

    /// PostHog reads this token from a UIKit view's accessibility identifier and
    /// hides the view in replays. Drawing canvases, the camera preview and the
    /// Ludo board carry it, because the automatic masking misses them.
    nonisolated static let hiddenFromReplaysAccessibilityToken = "ph-no-capture"

    private static let sharingKey = "analytics.sharesUsage"
    /// Set while an account is being deleted. The next launch deletes PostHog's
    /// files before it starts.
    private static let deletesLocalDataKey = "analytics.deletesLocalDataOnLaunch"

    /// Whose use PostHog counts.
    enum Account: Equatable {
        /// The app has not decided yet, as at launch.
        case unknown
        /// Nobody, as while signed out or while the account is being deleted.
        case signedOut
        case signedIn(userID: String)
    }

    /// PostHog is running in this process. It never starts while sharing is off.
    private static var isRunning = false
    /// The account and its couple, kept so that turning sharing on can tie
    /// PostHog to them.
    private static var account = Account.unknown
    private static var coupleID: UUID?

    /// Starts PostHog at launch, unless sharing is off.
    static func configure() {
        guard let key = projectKey else {
            return
        }
        if UserDefaults.standard.bool(forKey: deletesLocalDataKey) {
            deleteLocalData(projectKey: key)
            UserDefaults.standard.removeObject(forKey: deletesLocalDataKey)
        }
        guard isSharingEnabled else {
            // PostHog's opt-out stops new events but still sends what its queues
            // and crash reporter hold, so it does not start at all. What an earlier
            // run left on the phone is deleted while nothing is running.
            deleteLocalData(projectKey: key)
            return
        }
        start(projectKey: key)
    }

    /// Ties later events to `account`. Leaving an account starts a fresh
    /// anonymous visitor, so whoever signs in next is not mixed with it.
    static func follow(_ account: Account) {
        self.account = account
        applyIdentity()
    }

    /// Stops counting for the account before the server asks PostHog to delete it.
    /// PostHog deletes only what reached it before that request, and `reset()`
    /// keeps the queue under the old account, so nothing more goes out in this
    /// run, and the next launch deletes what was left.
    static func accountDeletionStarted() {
        AnalyticsUploadGate.isOpen.withLock { $0 = false }
        UserDefaults.standard.set(true, forKey: deletesLocalDataKey)
        follow(.signedOut)
    }

    /// The account still exists, so what was queued for it may go out again.
    /// The root view follows the account again once its screen is back.
    static func accountDeletionFailed() {
        UserDefaults.standard.removeObject(forKey: deletesLocalDataKey)
        AnalyticsUploadGate.isOpen.withLock { $0 = isSharingEnabled }
    }

    /// Adds the couple to every later event, so both partners' use can be
    /// counted together.
    static func setCouple(_ coupleID: UUID?) {
        self.coupleID = coupleID
        applyEventProperties()
    }

    static func screen(_ name: String) {
        guard isActive else {
            return
        }
        PostHogSDK.shared.screen(name)
    }

    /// Whether this phone shares usage statistics, replays and crash reports.
    /// Saved here rather than in PostHog, because PostHog's `reset()` forgets
    /// its own copy.
    static var isSharingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: sharingKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: sharingKey)
            guard let key = projectKey else {
                return
            }
            AnalyticsUploadGate.isOpen.withLock { $0 = newValue }
            if !newValue {
                // Stops new events, replays and crash reports. The gate holds back
                // what PostHog queued earlier, and the next launch deletes it.
                PostHogSDK.shared.optOut()
            } else if isRunning {
                PostHogSDK.shared.optIn()
                // Identity changes are skipped while sharing is off.
                applyIdentity()
                applyEventProperties()
            } else {
                start(projectKey: key)
            }
        }
    }

    /// Whether this build sends anything at all, so Settings can hide the switch
    /// in a build without a key.
    static var isAvailable: Bool {
        projectKey != nil
    }

    private static var isActive: Bool {
        isRunning && isSharingEnabled
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

        config.sessionReplay = true
        // Pixels instead of a wireframe, because a SwiftUI wireframe is mostly
        // empty boxes. All text and images are hidden either way.
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.maskAllTextInputs = true
        config.sessionReplayConfig.maskAllImages = true
        // Touch points are sent unmasked, and on a canvas they trace the drawing.
        config.sessionReplayConfig.captureTouches = false
        config.rageClickConfig.enabled = false
        // Request URLs include signed media links.
        config.sessionReplayConfig.captureNetworkTelemetry = false

        config.errorTrackingConfig.autoCapture = true

        let session = URLSessionConfiguration.default
        session.protocolClasses = [AnalyticsUploadGate.self] + (session.protocolClasses ?? [])
        config.urlSessionConfiguration = session
        AnalyticsUploadGate.isOpen.withLock { $0 = true }

        PostHogSDK.shared.setup(config)
        isRunning = true
        applyIdentity()
        applyEventProperties()

        PaeoniaConvexClient.setWriteObserver { path in
            guard !uncountedFunctions.contains(path) else {
                return
            }
            PostHogSDK.shared.capture(path)
        }
    }

    /// Makes PostHog's person match `account`. `identify` keeps an earlier account
    /// it was given, such as one whose session ended while the app was closed, so
    /// that one is reset first.
    private static func applyIdentity() {
        // `reset()` reloads feature flags, a request that must not go out while
        // sharing is off. Turning sharing on applies the identity again.
        guard isActive else {
            return
        }
        let sdk = PostHogSDK.shared
        let distinctID = sdk.getDistinctId()
        let identifiedAs = distinctID == sdk.getAnonymousId() ? nil : distinctID
        switch account {
        case .unknown:
            return
        case .signedOut:
            if identifiedAs != nil {
                resetKeepingEventProperties()
            }
        case let .signedIn(userID):
            if let identifiedAs, identifiedAs != userID {
                resetKeepingEventProperties()
            }
            sdk.identify(userID)
        }
    }

    /// `reset()` also drops the properties added to every event.
    private static func resetKeepingEventProperties() {
        PostHogSDK.shared.reset()
        applyEventProperties()
    }

    private static func applyEventProperties() {
        guard isActive else {
            return
        }
        #if DEBUG
        PostHogSDK.shared.register(["debug_build": true])
        #endif
        if let coupleID {
            PostHogSDK.shared.register(["couple_id": coupleID.uuidString.lowercased()])
        } else {
            PostHogSDK.shared.unregister("couple_id")
        }
    }

    /// Deletes PostHog's files: queued events and replay frames, the stored
    /// identity, and the crash reporter's waiting reports. Only safe while
    /// PostHog is not running.
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
/// Fails every PostHog request while sharing is off. PostHog's opt-out stops new
/// events but keeps sending what it queued before, and it has no way to drop
/// that queue. A failed upload stays queued, and the next launch deletes it.
nonisolated final class AnalyticsUploadGate: URLProtocol, @unchecked Sendable {
    static let isOpen = Mutex(true)

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
