import Foundation
#if DEBUG
import OSLog
#endif

/// Registers this device's APNs token so the backend can send the silent push
/// that wakes the app to sync a partner's new drawing.
nonisolated protocol PushRegistering: Sendable {
    func registerDevice(pushToken: String) async
}

actor ConvexPushRegistrationService: PushRegistering {
    /// Sandbox for development builds, production otherwise — this selects the
    /// correct APNs endpoint server-side.
    nonisolated static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private let client: PaeoniaConvexClient
    private let currentAccountID: @Sendable () async -> String?
    private let fingerprintStore: PushRegistrationFingerprintStore

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Push"
    )
    #endif

    init(
        client: PaeoniaConvexClient,
        currentAccountID: @escaping @Sendable () async -> String? = { PaeoniaClerk.currentAccountID() },
        fingerprintStore: PushRegistrationFingerprintStore = PushRegistrationFingerprintStore(channel: .device)
    ) {
        self.client = client
        self.currentAccountID = currentAccountID
        self.fingerprintStore = fingerprintStore
    }

    func registerDevice(pushToken: String) async {
        // iOS re-delivers the APNs token on every foreground; without an active
        // session there is nobody to register for, so skip rather than send an
        // anonymous request and let a later authenticated activation register.
        guard let accountID = await currentAccountID() else {
            return
        }

        let fingerprint = fingerprint(accountID: accountID, token: pushToken)
        let now = Date()
        guard PushRegistrationGate.shouldSend(
            current: fingerprint,
            lastSent: fingerprintStore.lastSent(),
            now: now
        ) else {
            return
        }

        do {
            let deviceID: UUID = try await client.mutation(
                "identity:register_user_device",
                args: RegisterDeviceRequest(
                    pushToken: pushToken,
                    apnsEnvironment: Self.apnsEnvironment,
                    locale: Locale.current.identifier,
                    timeZoneID: TimeZone.current.identifier,
                    appVersion: Self.appVersion
                )
            )
            fingerprintStore.recordSent(
                PushRegistrationRecord(fingerprint: fingerprint, sentAt: now, deviceID: deviceID)
            )
        } catch {
            // Best effort: a failed registration just means no silent push yet;
            // on-open sync still delivers the partner's drawing.
            #if DEBUG
            logger.error("Device registration failed: \(String(describing: error))")
            #endif
        }
    }

    private func fingerprint(accountID: String, token: String) -> String {
        PushRegistrationGate.fingerprint(
            PushRegistrationInputs(
                userID: accountID,
                platform: "ios",
                token: token,
                apnsEnvironment: Self.apnsEnvironment,
                locale: Locale.current.identifier,
                timeZoneID: TimeZone.current.identifier,
                appVersion: Self.appVersion
            )
        )
    }

    nonisolated static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Stops the signed-in account's alerts on this phone. The backend keeps a
    /// device until another account registers the same token, so without this
    /// the partner's alerts keep arriving after sign-out.
    ///
    /// Call it before signing out of Clerk, while requests still carry the
    /// account's token. It waits at most `timeout` and never fails sign-out.
    /// The stored registration is cleared either way, so the next sign-in
    /// registers the phone again.
    nonisolated static func disableRegisteredDevice(
        client: PaeoniaConvexClient,
        fingerprintStore: PushRegistrationFingerprintStore = PushRegistrationFingerprintStore(channel: .device),
        timeout: Duration = .seconds(3)
    ) async {
        defer { fingerprintStore.reset() }
        guard let deviceID = fingerprintStore.lastSent()?.deviceID else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let _: Bool? = try? await client.mutation(
                    "identity:disable_user_device",
                    args: DisableDeviceRequest(deviceID: deviceID)
                )
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            await group.next()
            group.cancelAll()
        }
    }
}

/// Used when no Convex client is configured.
nonisolated struct NoOpPushRegistration: PushRegistering {
    func registerDevice(pushToken: String) {}
}

nonisolated enum PushRegistrationServiceFactory {
    static func makeDefault() -> any PushRegistering {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return NoOpPushRegistration()
        }
        return ConvexPushRegistrationService(client: client)
    }
}

nonisolated private struct DisableDeviceRequest: Encodable {
    let deviceID: UUID

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
    }
}

nonisolated private struct RegisterDeviceRequest: Encodable {
    let platform = "ios"
    let pushToken: String
    let apnsEnvironment: String
    let locale: String?
    let timeZoneID: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case platform = "p_platform"
        case pushToken = "p_push_token"
        case apnsEnvironment = "p_apns_environment"
        case locale = "p_locale"
        case timeZoneID = "p_time_zone_id"
        case appVersion = "p_app_version"
    }
}
