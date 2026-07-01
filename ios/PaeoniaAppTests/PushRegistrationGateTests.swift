import Foundation
import Testing
@testable import PaeoniaApp

struct PushRegistrationGateTests {
    private func fingerprint(
        userID: UUID? = UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        token: String = "token-a"
    ) -> String {
        PushRegistrationGate.fingerprint(
            PushRegistrationInputs(
                userID: userID,
                platform: "ios",
                token: token,
                apnsEnvironment: "sandbox",
                locale: "en_US",
                timeZoneID: "Europe/Oslo",
                appVersion: "1.0"
            )
        )
    }

    @Test func sendsWhenNothingHasBeenSentYet() {
        #expect(PushRegistrationGate.shouldSend(current: fingerprint(), lastSent: nil, now: Date()))
    }

    @Test func skipsWhenFingerprintUnchangedWithinHeartbeatWindow() {
        let stored = fingerprint()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = PushRegistrationRecord(fingerprint: stored, sentAt: now.addingTimeInterval(-60 * 60))
        #expect(!PushRegistrationGate.shouldSend(current: stored, lastSent: last, now: now))
    }

    @Test func resendsWhenTokenChanges() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = PushRegistrationRecord(fingerprint: fingerprint(token: "token-a"), sentAt: now)
        #expect(PushRegistrationGate.shouldSend(current: fingerprint(token: "token-b"), lastSent: last, now: now))
    }

    @Test func resendsAfterHeartbeatIntervalEvenWhenUnchanged() {
        let stored = fingerprint()
        let sentAt = Date(timeIntervalSince1970: 1_000_000)
        let last = PushRegistrationRecord(fingerprint: stored, sentAt: sentAt)
        let now = sentAt.addingTimeInterval(PushRegistrationGate.heartbeatInterval)
        #expect(PushRegistrationGate.shouldSend(current: stored, lastSent: last, now: now))
    }

    @Test func fingerprintChangesWithUser() {
        let firstUser = fingerprint(userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let secondUser = fingerprint(userID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(firstUser != secondUser)
    }

    @Test func storeRoundTripsAndResetForcesResend() throws {
        let suiteName = "PushRegistrationGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PushRegistrationFingerprintStore(channel: .device, defaults: defaults)
        let stored = fingerprint()
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(store.lastSent() == nil)

        store.recordSent(PushRegistrationRecord(fingerprint: stored, sentAt: now))
        #expect(store.lastSent() == PushRegistrationRecord(fingerprint: stored, sentAt: now))
        #expect(!PushRegistrationGate.shouldSend(current: stored, lastSent: store.lastSent(), now: now))

        // Signing out clears the record, so the next sign-in re-registers.
        store.reset()
        #expect(store.lastSent() == nil)
        #expect(PushRegistrationGate.shouldSend(current: stored, lastSent: store.lastSent(), now: now))
    }

    @Test func resetAllClearsBothChannels() throws {
        let suiteName = "PushRegistrationGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let device = PushRegistrationFingerprintStore(channel: .device, defaults: defaults)
        let widget = PushRegistrationFingerprintStore(channel: .widget, defaults: defaults)
        let record = PushRegistrationRecord(fingerprint: fingerprint(), sentAt: Date(timeIntervalSince1970: 1))
        device.recordSent(record)
        widget.recordSent(record)

        PushRegistrationFingerprintStore.resetAll(defaults: defaults)

        #expect(device.lastSent() == nil)
        #expect(widget.lastSent() == nil)
    }
}
