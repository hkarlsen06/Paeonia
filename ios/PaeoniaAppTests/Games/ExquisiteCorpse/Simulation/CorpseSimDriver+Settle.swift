import Foundation
@testable import PaeoniaApp

// Waiting for the phones to go quiet, and bringing the network back so every queue can drain.
extension CorpseSimDriver {
    /// What the server, the relay and every phone look like, for spotting when they stopped changing.
    private func worldFingerprint(includingRelay: Bool) async -> String {
        var parts = ["\(server.viewVersion)"]
        if includingRelay {
            parts.append("\(relay.isIdle)")
        }
        for phone in phones {
            parts.append(await phone.fingerprint())
        }
        return parts.joined(separator: "§")
    }

    /// Lets the tasks run until nothing changes for a few rounds: the relay is
    /// idle, no request is on its way except held ones, and every phone's
    /// screen, queue and cache stay the same.
    func pump(minRounds: Int = 4, maxRounds: Int = 400) async {
        var last = ""
        var stable = 0
        for round in 0..<maxRounds {
            for phone in phones {
                phone.updateScreens()
                await phone.feedTick()
            }
            try? await Task.sleep(for: .milliseconds(2))
            let fingerprint = await worldFingerprint(includingRelay: true)
            guard fingerprint == last, relay.isIdle,
                  !phones.contains(where: { $0.drawingStore.hasUnfinishedBackgroundSave })
            else {
                stable = 0
                last = fingerprint
                continue
            }
            stable += 1
            if stable >= 3, round >= minRounds { return }
        }
        log.add("pump did not settle")
    }

    /// Brings the network up and the faults down, then lets every queue drain.
    /// A person whose strip or reveal failed to load taps "Try again".
    func settle() async {
        for phone in phones {
            phone.network.faultsEnabled = false
            phone.setOnline(true)
            phone.network.releaseHeld(deliverAll: true)
            phone.isFeedOutage = false
            phone.isFeedDelayed = false
        }
        relay.reapGhosts()
        relay.expireSessions()
        var last = ""
        for _ in 0..<40 {
            for phone in phones where phone.isAlive {
                phone.reconnectRelay()
            }
            for phone in phones where phone.isAlive && phone.isForeground {
                await phone.sync()
                phone.retryFailedLoads()
            }
            await pump()
            let fingerprint = await worldFingerprint(includingRelay: false)
            if fingerprint == last { break }
            last = fingerprint
        }
        for phone in phones {
            phone.network.faultsEnabled = true
        }
    }

    func settleAndCheck() async throws {
        log.add("settle")
        settleCount += 1
        await settle()
        try await checkSettled()
    }
}
