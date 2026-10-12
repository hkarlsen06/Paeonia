import Foundation
import WidgetKit
#if DEBUG
import OSLog
#endif

nonisolated protocol WidgetPushRegistering: Sendable {
    func registerCurrentWidgetPushToken() async
}

actor ConvexWidgetPushRegistrationService: WidgetPushRegistering {
    private let client: PaeoniaConvexClient
    private let currentAccountID: @Sendable () async -> String?
    private let tokenStore: PaeoniaWidgetPushTokenStore
    private let fingerprintStore: PushRegistrationFingerprintStore

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "WidgetPush"
    )
    #endif

    init(
        client: PaeoniaConvexClient,
        currentAccountID: @escaping @Sendable () async -> String? = { PaeoniaClerk.currentAccountID() },
        tokenStore: PaeoniaWidgetPushTokenStore = .shared,
        fingerprintStore: PushRegistrationFingerprintStore = PushRegistrationFingerprintStore(channel: .widget)
    ) {
        self.client = client
        self.currentAccountID = currentAccountID
        self.tokenStore = tokenStore
        self.fingerprintStore = fingerprintStore
    }

    func registerCurrentWidgetPushToken() async {
        guard let token = await currentWidgetPushToken() else {
            return
        }

        // No active session: don't send an anonymous registration; a later
        // authenticated activation will register once auth is restored.
        guard let accountID = await currentAccountID() else {
            return
        }

        let fingerprint = fingerprint(accountID: accountID, token: token)
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
                "widget:register_widget_push_device",
                args: RegisterWidgetPushDeviceRequest(
                    widgetKind: PaeoniaAppGroup.widgetKind,
                    widgetPushToken: token,
                    apnsEnvironment: ConvexPushRegistrationService.apnsEnvironment,
                    locale: Locale.current.identifier,
                    timeZoneID: TimeZone.current.identifier,
                    appVersion: ConvexPushRegistrationService.appVersion
                )
            )
            fingerprintStore.recordSent(PushRegistrationRecord(fingerprint: fingerprint, sentAt: now, deviceID: deviceID))
        } catch {
            #if DEBUG
            logger.error("Widget push registration failed: \(String(describing: error))")
            #endif
        }
    }

    private func fingerprint(accountID: String, token: String) -> String {
        PushRegistrationGate.fingerprint(
            PushRegistrationInputs(
                userID: accountID,
                platform: PaeoniaAppGroup.widgetKind,
                token: token,
                apnsEnvironment: ConvexPushRegistrationService.apnsEnvironment,
                locale: Locale.current.identifier,
                timeZoneID: TimeZone.current.identifier,
                appVersion: ConvexPushRegistrationService.appVersion
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
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return NoOpWidgetPushRegistration()
        }
        return ConvexWidgetPushRegistrationService(client: client)
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
