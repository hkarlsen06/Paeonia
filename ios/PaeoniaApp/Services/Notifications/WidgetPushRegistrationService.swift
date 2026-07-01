import Foundation
import Supabase
import WidgetKit
#if DEBUG
import OSLog
#endif

nonisolated protocol WidgetPushRegistering: Sendable {
    func registerCurrentWidgetPushToken() async
}

actor SupabaseWidgetPushRegistrationService: WidgetPushRegistering {
    private let client: SupabaseClient
    private let tokenStore: PaeoniaWidgetPushTokenStore
    private let fingerprintStore: PushRegistrationFingerprintStore

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "WidgetPush"
    )
    #endif

    init(
        client: SupabaseClient,
        tokenStore: PaeoniaWidgetPushTokenStore = .shared,
        fingerprintStore: PushRegistrationFingerprintStore = PushRegistrationFingerprintStore(channel: .widget)
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.fingerprintStore = fingerprintStore
    }

    func registerCurrentWidgetPushToken() async {
        guard let token = await currentWidgetPushToken() else {
            return
        }

        // No active session: don't send an anonymous registration; a later
        // authenticated activation will register once auth is restored.
        guard let session = try? await client.auth.session else {
            return
        }

        let fingerprint = fingerprint(userID: session.user.id, token: token)
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
                    "register_widget_push_device",
                    params: RegisterWidgetPushDeviceRequest(
                        widgetKind: PaeoniaAppGroup.widgetKind,
                        widgetPushToken: token,
                        apnsEnvironment: SupabasePushRegistrationService.apnsEnvironment,
                        locale: Locale.current.identifier,
                        timeZoneID: TimeZone.current.identifier,
                        appVersion: SupabasePushRegistrationService.appVersion
                    )
                )
                .execute()
                .value
            fingerprintStore.recordSent(PushRegistrationRecord(fingerprint: fingerprint, sentAt: now))
        } catch {
            #if DEBUG
            logger.error("Widget push registration failed: \(String(describing: error))")
            #endif
        }
    }

    private func fingerprint(userID: UUID, token: String) -> String {
        PushRegistrationGate.fingerprint(
            PushRegistrationInputs(
                userID: userID,
                platform: PaeoniaAppGroup.widgetKind,
                token: token,
                apnsEnvironment: SupabasePushRegistrationService.apnsEnvironment,
                locale: Locale.current.identifier,
                timeZoneID: TimeZone.current.identifier,
                appVersion: SupabasePushRegistrationService.appVersion
            )
        )
    }

    private func currentWidgetPushToken() async -> String? {
        if let pushInfo = await WidgetCenter.shared.currentPushInfo {
            let token = pushInfo.token.paeoniaHexString
            tokenStore.save(token: token, widgetKinds: [PaeoniaAppGroup.widgetKind])
            return token
        }

        return tokenStore.loadToken(forWidgetKind: PaeoniaAppGroup.widgetKind)
    }
}

nonisolated struct NoOpWidgetPushRegistration: WidgetPushRegistering {
    func registerCurrentWidgetPushToken() async {}
}

nonisolated enum WidgetPushRegistrationServiceFactory {
    static func makeDefault() -> any WidgetPushRegistering {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return NoOpWidgetPushRegistration()
        }
        return SupabaseWidgetPushRegistrationService(client: client)
    }
}

private nonisolated struct RegisterWidgetPushDeviceRequest: Encodable, Sendable {
    let widgetKind: String
    let widgetPushToken: String
    let apnsEnvironment: String
    let locale: String
    let timeZoneID: String
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case widgetKind = "p_widget_kind"
        case widgetPushToken = "p_widget_push_token"
        case apnsEnvironment = "p_apns_environment"
        case locale = "p_locale"
        case timeZoneID = "p_time_zone_id"
        case appVersion = "p_app_version"
    }
}

private extension Data {
    nonisolated var paeoniaHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
