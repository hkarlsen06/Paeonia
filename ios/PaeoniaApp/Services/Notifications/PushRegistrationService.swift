import Foundation
import Supabase
#if DEBUG
import OSLog
#endif

/// Registers this device's APNs token so the backend can send the silent push
/// that wakes the app to sync a partner's new drawing.
nonisolated protocol PushRegistering: Sendable {
    func registerDevice(pushToken: String) async
}

actor SupabasePushRegistrationService: PushRegistering {
    /// Sandbox for development builds, production otherwise — this selects the
    /// correct APNs endpoint server-side.
    nonisolated static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private let client: SupabaseClient
    private let fingerprintStore: PushRegistrationFingerprintStore

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Push"
    )
    #endif

    init(
        client: SupabaseClient,
        fingerprintStore: PushRegistrationFingerprintStore = PushRegistrationFingerprintStore(channel: .device)
    ) {
        self.client = client
        self.fingerprintStore = fingerprintStore
    }

    func registerDevice(pushToken: String) async {
        // iOS re-delivers the APNs token on every foreground; without an active
        // session there is nobody to register for, so skip rather than fire an
        // anonymous RPC and let a later authenticated activation register.
        guard let session = try? await client.auth.session else {
            return
        }

        let fingerprint = fingerprint(userID: session.user.id, token: pushToken)
        let now = Date()
        guard PushRegistrationGate.shouldSend(
            current: fingerprint,
            lastSent: fingerprintStore.lastSent(),
            now: now
        ) else {
            return
        }

        do {
            let _: UUID = try await client
                .rpc(
                    "register_user_device",
                    params: RegisterDeviceRequest(
                        pushToken: pushToken,
                        apnsEnvironment: Self.apnsEnvironment,
                        locale: Locale.current.identifier,
                        timeZoneID: TimeZone.current.identifier,
                        appVersion: Self.appVersion
                    )
                )
                .execute()
                .value
            fingerprintStore.recordSent(PushRegistrationRecord(fingerprint: fingerprint, sentAt: now))
        } catch {
            // Best effort: a failed registration just means no silent push yet;
            // on-open sync still delivers the partner's drawing.
            #if DEBUG
            logger.error("Device registration failed: \(String(describing: error))")
            #endif
        }
    }

    private func fingerprint(userID: UUID, token: String) -> String {
        PushRegistrationGate.fingerprint(
            PushRegistrationInputs(
                userID: userID,
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
}

/// Used when no Supabase client is configured.
nonisolated struct NoOpPushRegistration: PushRegistering {
    func registerDevice(pushToken: String) {}
}

nonisolated enum PushRegistrationServiceFactory {
    static func makeDefault() -> any PushRegistering {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return NoOpPushRegistration()
        }
        return SupabasePushRegistrationService(client: client)
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
