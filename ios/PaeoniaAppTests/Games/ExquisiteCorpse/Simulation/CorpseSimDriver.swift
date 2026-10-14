import Foundation
import PencilKit
@testable import PaeoniaApp

/// Plays Exquisite corpse on two phones with seeded randomness and checks the
/// invariants each time the network is up and the queues have drained.
///
/// Each step one phone acts like a person (draws above and below the fold, clears,
/// asks for an idea, taps Done, continues from the reveal, stars, invites, leaves
/// the screen, tries sending again) or the world does something to it (offline,
/// background, force quit, a dropped socket, a stalled live feed, time passing, a
/// request held on the network).
@MainActor
final class CorpseSimDriver {
    struct Config {
        var steps = 150
        var settleChance = 0.25
        /// The fault rates of each phone's network, scaled.
        var faultScale = 1.0
        /// The share of steps where the world acts instead of a person.
        var chaosRate = 0.38
    }

    let seed: UInt64
    let config: Config
    let log = SimLog()
    let clock: SimClock
    let server: CorpseSimServer
    let relay: SimRelay
    let phones: [CorpseSimPhone]
    var random: SimRandom

    /// What each phone's canvas holds for the part the person is drawing, as they left it.
    var drawn: [String: CorpseSimDrawing] = [:]
    /// The figures each person moved past with Continue.
    var continued: [String: Set<UUID>] = [:]
    /// The last star each person set on a figure.
    var starIntent: [String: [UUID: Bool]] = [:]
    var settlesWithoutProgress = 0
    var lastProgressVersion = -1
    var settleCount = 0
    var pendingFailure: SimFailure?
    private var lastHeartbeat: Date
    private var hasWeekPassed = false
    /// Actions run back to back without waiting for the phones.
    var isBurst = false

    init(seed: UInt64, config: Config = Config()) {
        self.seed = seed
        self.config = config
        var random = SimRandom(seed: seed)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        clock = SimClock(start: start)
        lastHeartbeat = start
        let userA = UUID()
        let userB = UUID()
        server = CorpseSimServer(users: [userA, userB], clock: clock)
        relay = SimRelay(clock: clock, log: log)
        let sides: [CGFloat] = [300, 320, 360, 390]
        phones = [
            CorpseSimPhone(
                name: "A", userID: userA, partnerID: userB, server: server, relay: relay, clock: clock,
                log: log, random: random.split(), canvasSide: random.pick(sides)
            ),
            CorpseSimPhone(
                name: "B", userID: userB, partnerID: userA, server: server, relay: relay, clock: clock,
                log: log, random: random.split(), canvasSide: random.pick(sides)
            ),
        ]
        // Each seed gets its own weather: a calm network, an ordinary one, or a
        // bad one, sometimes with a server that keeps refusing with a bare error.
        let weather = config.faultScale == 0 ? 0 : random.pick([0.5, 1, 2, 3])
        let refusals = random.chance(0.25) ? 6.0 : 1.0
        for phone in phones {
            phone.network.dropRate *= config.faultScale * weather
            phone.network.serverErrorRate *= config.faultScale * weather * refusals
            phone.network.holdRate *= config.faultScale * weather
        }
        self.random = random
    }

    func partner(of phone: CorpseSimPhone) -> CorpseSimPhone {
        phone === phones[0] ? phones[1] : phones[0]
    }

    // MARK: - Running

    func run() async throws {
        defer { shutDown() }
        try await setUp()
        for step in 1...config.steps {
            log.step = step
            // Sometimes both people act at once, with no time for either phone to settle in between.
            // One action each: a person cannot act twice before their own phone shows the first move.
            if random.chance(0.25) {
                isBurst = true
                let first = random.pick(phones)
                await doStep(on: first)
                await doStep(on: partner(of: first))
                isBurst = false
            } else {
                await doStep()
            }
            await pump()
            try await checkAlways()
            if random.chance(config.settleChance) {
                try await settleAndCheck()
            }
        }
        log.step = config.steps + 1
        try await settleAndCheck()
    }

    /// A line about what the seed played, so a quiet run can be told from a thorough one.
    func summary() async -> String {
        let finished = server.figures.filter { $0.finishedAt != nil }.count
        var parts = [
            "seed \(seed)", "parts \(server.parts.count)", "figures \(finished)",
            "ideas \(server.parts.filter { $0.idea != nil }.count)", "settles \(settleCount)",
            "downloads \(server.downloads.count)",
        ]
        for phone in phones {
            let ledger = await phone.pending.ledger
            let terminal = ledger.filter { if case .terminal = $0.outcome { true } else { false } }.count
            parts.append(
                "\(phone.name): launches \(phone.launchCount) moves \(ledger.count) dropped \(terminal) "
                    + "notices \(phone.notices.count) strips \(phone.stripsSent) calls \(phone.network.callCount)"
            )
        }
        return parts.joined(separator: ", ")
    }

    /// Every write each phone queued and how it ended, for a failure report.
    func ledgerDump() async -> String {
        var lines: [String] = []
        for phone in phones {
            for entry in await phone.pending.ledger {
                let operation = entry.operationID.uuidString.prefix(6)
                lines.append("\(phone.name) \(entry.kind.rawValue) op \(operation) -> \(entry.outcome)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func shutDown() {
        for phone in phones {
            phone.shutDown()
        }
    }

    func setUp() async throws {
        for phone in phones {
            phone.network.faultsEnabled = false
            phone.launch()
        }
        await pump()
        let first = random.pick(phones)
        first.openScreen()
        await pump()
        partner(of: first).openScreen()
        await settle()
        guard server.game != nil else {
            throw SimFailure(message: "setup: the game was never created")
        }
        for phone in phones {
            phone.network.faultsEnabled = true
        }
    }

    // MARK: - One step

    private func doStep(on chosen: CorpseSimPhone? = nil) async {
        let phone = chosen ?? random.pick(phones)
        if random.unit() >= config.chaosRate {
            await act(as: phone)
        } else {
            chaos(on: phone)
        }
    }

    /// What the world does: networks, the app's life, the relay, the clock.
    private func chaos(on phone: CorpseSimPhone) {
        let events = appEvents(phone) + worldEvents(phone)
        let event = random.weighted(events)
        event()
    }

    private func appEvents(_ phone: CorpseSimPhone) -> [(() -> Void, Double)] {
        let isOnline = phone.network.isOnline
        return [
            ({ phone.setOnline(false) }, isOnline ? 4 : 0),
            ({ phone.setOnline(true) }, isOnline ? 0 : 8),
            ({ phone.moveToBackground() }, phone.isForeground ? 3 : 0),
            ({ phone.moveToForeground() }, phone.isForeground ? 0 : 6),
            ({ phone.closeScreen() }, 2),
            ({ phone.forceQuit(closesSocket: self.random.chance(0.6)) }, 1.5),
            ({
                self.log.add("\(phone.name) socket drop")
                phone.socket?.dropSilently()
            }, 2),
            ({ phone.reconnectRelay() }, 5),
            ({
                self.log.add("\(phone.name) retry timer")
                Task { await phone.sync() }
            }, 3),
        ]
    }

    private func worldEvents(_ phone: CorpseSimPhone) -> [(() -> Void, Double)] {
        [
            ({ self.relay.reapGhosts() }, 2),
            ({
                phone.isFeedOutage.toggle()
                self.log.add("\(phone.name) feed outage \(phone.isFeedOutage)")
            }, 1.5),
            ({
                phone.isFeedDelayed.toggle()
                self.log.add("\(phone.name) feed delayed \(phone.isFeedDelayed)")
            }, 1.5),
            ({ phone.network.releaseHeld(count: self.random.int(1...max(1, phone.network.heldCount))) },
             phone.network.heldCount > 0 ? 6 : 0),
            ({ self.advanceTime(Double(self.random.int(1...6))) }, 6),
            ({ self.advanceTime(Double(self.random.int(20...45))) }, 3),
            ({ self.advanceTime(Double(self.random.int(120...900))) }, 0.6),
            ({ self.passWeek() }, hasWeekPassed ? 0 : 0.25),
        ]
    }

    /// Only once a run: the app renews a gone upload at most once a day of real time.
    private func passWeek() {
        hasWeekPassed = true
        advanceTime(8 * 86_400)
        log.add("server swept \(server.sweepOrphanedUploads()) unused uploads")
    }

    func advanceTime(_ seconds: TimeInterval) {
        clock.advance(seconds)
        log.add("time +\(Int(seconds))s")
        relay.expireSessions()
        server.expirePresence()
        let beat = clock.now.timeIntervalSince(lastHeartbeat) >= 30
        if beat {
            lastHeartbeat = clock.now
        }
        for phone in phones {
            if beat {
                phone.heartbeat()
            }
            phone.tick()
        }
    }
}
