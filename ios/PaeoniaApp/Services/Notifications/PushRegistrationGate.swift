import CryptoKit
import Foundation

/// A device-registration attempt that actually reached the backend, remembered
/// so we don't re-send an identical registration on every scene activation.
nonisolated struct PushRegistrationRecord: Codable, Equatable, Sendable {
    let fingerprint: String
    let sentAt: Date
}

/// Every field a registration RPC sends. A change to any of these should
/// re-register the device; nothing else should.
nonisolated struct PushRegistrationInputs: Sendable {
    let userID: UUID?
    let platform: String
    let token: String
    let apnsEnvironment: String
    let locale: String
    let timeZoneID: String
    let appVersion: String?
}

/// Decides whether a device / widget push-registration RPC needs to be sent.
///
/// iOS re-delivers the APNs token on every foreground, and the app also pings
/// widget registration on every `.active` transition. Left ungated, each one
/// fired `register_user_device` / `register_widget_push_device` unconditionally
/// — many identical writes per day per device. This gate skips the call when
/// nothing the backend cares about has changed and the last successful send is
/// still recent, while a daily heartbeat keeps the server's `last_seen_at`
/// fresh for stale-device cleanup.
nonisolated enum PushRegistrationGate {
    /// Re-send at least this often even when nothing changed, so the backend's
    /// last-seen bookkeeping stays useful.
    static let heartbeatInterval: TimeInterval = 24 * 60 * 60

    static func shouldSend(
        current: String,
        lastSent: PushRegistrationRecord?,
        now: Date,
        heartbeatInterval: TimeInterval = heartbeatInterval
    ) -> Bool {
        guard let lastSent else {
            return true
        }
        if lastSent.fingerprint != current {
            return true
        }
        return now.timeIntervalSince(lastSent.sentAt) >= heartbeatInterval
    }

    /// A stable hash of every field the registration RPC sends. The user id is
    /// part of it so switching accounts always re-registers; a sign out (which
    /// clears the stored record) followed by a sign back in re-registers too.
    static func fingerprint(_ inputs: PushRegistrationInputs) -> String {
        let material = [
            inputs.userID?.uuidString.lowercased() ?? "-",
            inputs.platform,
            inputs.token,
            inputs.apnsEnvironment,
            inputs.locale,
            inputs.timeZoneID,
            inputs.appVersion ?? "-"
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// UserDefaults-backed persistence for the last successful registration per
/// channel (main-app silent push vs. widget push).
nonisolated final class PushRegistrationFingerprintStore: @unchecked Sendable {
    enum Channel: String {
        case device = "paeonia.push.deviceRegistrationFingerprint"
        case widget = "paeonia.push.widgetRegistrationFingerprint"
    }

    private let defaults: UserDefaults
    private let key: String

    init(channel: Channel, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = channel.rawValue
    }

    func lastSent() -> PushRegistrationRecord? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(PushRegistrationRecord.self, from: data)
    }

    func recordSent(_ record: PushRegistrationRecord) {
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    /// Clears every channel's remembered registration so the next sign-in
    /// re-registers this device from scratch.
    static func resetAll(defaults: UserDefaults = .standard) {
        PushRegistrationFingerprintStore(channel: .device, defaults: defaults).reset()
        PushRegistrationFingerprintStore(channel: .widget, defaults: defaults).reset()
    }
}
