import Foundation
import PushKit

/// The partner's call ringing this phone, from a VoIP push or from `calls:get_live_call`.
nonisolated struct IncomingRing: Equatable, Sendable {
    /// How long a ring lasts when the push does not say (`RING_SECONDS` on the server).
    static let defaultRingDuration: TimeInterval = 45

    let callID: UUID
    let callerUserID: UUID
    let ringExpiresAt: Date
    /// False when the person keeps lock screen details private, so the call shows "Paeonia".
    let showsName: Bool
}

nonisolated extension IncomingRing {
    /// Reads the push `{type: "call", call_id, caller_user_id, ring_expires_at,
    /// lock_screen_detail_level}`. Nil when it is not a call push.
    init?(voipPayload payload: [AnyHashable: Any], now: Date = .now) {
        guard payload["type"] as? String == "call",
              let callID = (payload["call_id"] as? String).flatMap(UUID.init(uuidString:)),
              let callerUserID = (payload["caller_user_id"] as? String).flatMap(UUID.init(uuidString:))
        else {
            return nil
        }
        self.callID = callID
        self.callerUserID = callerUserID
        ringExpiresAt = Self.date(payload["ring_expires_at"]) ?? now + Self.defaultRingDuration
        showsName = payload["lock_screen_detail_level"] as? String == "descriptive"
    }

    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            return (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
        }
        // Milliseconds since 1970, as JavaScript counts them.
        if let milliseconds = value as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        return nil
    }
}

/// Whether incoming calls may show the partner's name on the lock screen. Each VoIP push carries
/// the person's choice. A ring from the open app has no push, so it uses the last one, and keeps
/// the name private until a push has said otherwise.
nonisolated enum CallLockScreenPrivacy {
    private static let key = "paeonia.calls.showsNameOnLockScreen"

    static var showsName: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func remember(showsName: Bool) {
        UserDefaults.standard.set(showsName, forKey: key)
    }
}

/// Receives VoIP pushes and this phone's PushKit token. PushKit calls it on the main queue.
final class CallPushRegistry: NSObject, PKPushRegistryDelegate {
    typealias PushHandler = (
        _ ring: IncomingRing?,
        _ mustReport: Bool,
        _ completion: @escaping @Sendable () -> Void
    ) -> Void

    private let registry = PKPushRegistry(queue: .main)
    private let onToken: (String?) -> Void
    private let onPush: PushHandler

    init(onToken: @escaping (String?) -> Void, onPush: @escaping PushHandler) {
        self.onToken = onToken
        self.onPush = onPush
        super.init()
        registry.delegate = self
        // Setting the types starts registration, so it comes last.
        registry.desiredPushTypes = [.voIP]
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        onToken(pushCredentials.token.paeoniaHexString)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        onToken(nil)
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingVoIPPushWith payload: PKPushPayload,
        metadata: PKVoIPPushMetadata,
        withCompletionHandler completion: @escaping @Sendable () -> Void
    ) {
        onPush(IncomingRing(voipPayload: payload.dictionaryPayload), metadata.mustReport, completion)
    }
}
