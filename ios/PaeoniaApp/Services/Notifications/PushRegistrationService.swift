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

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "Push"
    )
    #endif

    init(client: SupabaseClient) {
        self.client = client
    }

    func registerDevice(pushToken: String) async {
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
        } catch {
            // Best effort: a failed registration just means no silent push yet;
            // on-open sync still delivers the partner's drawing.
            #if DEBUG
            logger.error("Device registration failed: \(String(describing: error))")
            #endif
        }
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
