import Foundation
import PencilKit
@testable import PaeoniaApp

/// Plays Draw & Guess on two phones with seeded randomness and checks the
/// invariants each time the network is up and the queues have drained.
///
/// Each step one phone acts like a person (picks a word, draws, guesses, gives
/// up, saves or skips, continues, opens and leaves the screen) or the world
/// does something to it (offline, background, force quit, a dropped socket, a
/// live feed that stalls, time passing, a request held on the network).
@MainActor
final class SimDriver {
    struct Config {
        var steps = 220
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
    let server: SimServer
    let relay: SimRelay
    let phones: [SimPhone]
    var random: SimRandom

    /// Strokes on each phone's board for a round, as the person drew them.
    var boardStrokes: [String: (roundID: UUID, count: Int)] = [:]
    var settlesWithoutProgress = 0
    var lastProgressVersion = -1
    var lastHeartbeat: Date
    var hasWeekPassed = false
    /// The speed bonus tier each phone's screen promised for its last correct guess of a round.
    var promisedBonus: [UUID: Int] = [:]
    /// The hints each phone's screen had shown at its last correct guess of a round.
    var promisedHints: [UUID: Int] = [:]
    /// The slots a hint filled, by phone and round, as the person saw them.
    var hinted: [String: [Int]] = [:]
    /// Every reaction each guesser's screen showed for a finished round ("none" for a cleared one).
    /// A request held on the network may land after a newer one, so the server may hold any of them.
    var shownReactions: [UUID: Set<String>] = [:]
    /// Rounds whose drawing a person sent from their own phone.
    var drawnHere: Set<UUID> = []
    /// Actions run back to back without waiting for the phones.
    var isBurst = false
    var pendingFailure: SimFailure?
    private(set) var settleCount = 0

    init(seed: UInt64, config: Config = Config()) {
        self.seed = seed
        self.config = config
        var random = SimRandom(seed: seed)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        clock = SimClock(start: start)
        lastHeartbeat = start
        let userA = UUID()
        let userB = UUID()
        server = SimServer(users: [userA, userB], clock: clock, random: random.split())
        relay = SimRelay(clock: clock, log: log)
        let sides: [CGFloat] = [300, 320, 360, 390]
        phones = [
            SimPhone(
                name: "A", userID: userA, partnerID: userB, server: server, relay: relay, clock: clock,
                log: log, random: random.split(), canvasSide: random.pick(sides)
            ),
            SimPhone(
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
            try checkAlways()
            if random.chance(config.settleChance) {
                try await settleAndCheck()
            }
        }
        log.step = config.steps + 1
        try await settleAndCheck()
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
        first.games?.draftPlayStyle = random.chance(0.5) ? .against : .together
        first.games?.draftLanguage = random.chance(0.7) ? .en : .nb
        let style = first.games?.draftPlayStyle.rawValue ?? ""
        let language = first.games?.draftLanguage.rawValue ?? ""
        log.add("\(first.name) setup \(style) \(language)")
        await first.games?.finishSetup()
        await pump()
        first.openScreen()
        await pump()
        let other = partner(of: first)
        await other.games?.refresh()
        other.openScreen()
        await settle()
        guard server.game != nil else {
            throw SimFailure(message: "setup: the game was never created")
        }
        for phone in phones {
            phone.network.faultsEnabled = true
        }
    }

    // MARK: - One step

    private func doStep(on chosen: SimPhone? = nil) async {
        let phone = chosen ?? random.pick(phones)
        let roll = random.unit()
        if roll >= config.chaosRate {
            await act(as: phone)
        } else {
            chaos(on: phone)
        }
    }
}

extension SimDriver {
    /// A line about what the seed played, so a quiet run can be told from a thorough one.
    func summary() async -> String {
        let solved = server.rounds.filter { $0.state == .solved }.count
        let missed = server.rounds.filter { $0.state == .missed }.count
        var parts = [
            "seed \(seed)", "rounds \(server.rounds.count)", "solved \(solved)", "missed \(missed)",
            "hints \(server.rounds.reduce(0) { $0 + $1.hintsUsed })",
            "reactions \(server.rounds.filter { $0.reaction != nil }.count)",
            "attempts \(server.rounds.reduce(0) { $0 + $1.attempts.count })",
            "settles \(settleCount)",
        ]
        for phone in phones {
            let ledger = await phone.pending.ledger
            let terminal = ledger.filter { if case .terminal = $0.outcome { true } else { false } }.count
            parts.append(
                "\(phone.name): launches \(phone.launchCount) moves \(ledger.count) dropped \(terminal) "
                    + "notices \(phone.notices.count) calls \(phone.network.callCount)"
            )
        }
        return parts.joined(separator: ", ")
    }

    /// Every write each phone queued and how it ended, for a failure report.
    func ledgerDump() async -> String {
        var lines: [String] = []
        struct Round: Decodable { let roundID: UUID }
        for phone in phones {
            for entry in await phone.pending.ledger {
                let round = entry.requestData.flatMap { try? JSONDecoder().decode(Round.self, from: $0) }
                let roundTag = round?.roundID.uuidString.prefix(6) ?? "-"
                lines.append(
                    "\(phone.name) \(entry.kind.rawValue) round \(roundTag) "
                        + "op \(entry.operationID.uuidString.prefix(6)) -> \(entry.outcome)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Waiting for quiet

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
            var parts = ["\(server.viewVersion)", "\(relay.isIdle)"]
            for phone in phones {
                parts.append(await phone.fingerprint())
            }
            let fingerprint = parts.joined(separator: "§")
            if fingerprint == last, relay.isIdle {
                stable += 1
                if stable >= 3, round >= minRounds { return }
            } else {
                stable = 0
                last = fingerprint
            }
        }
        log.add("pump did not settle")
    }

    /// Brings the network up and the faults down, then lets every queue drain.
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
            }
            await pump()
            var parts = ["\(server.viewVersion)"]
            for phone in phones {
                parts.append(await phone.fingerprint())
            }
            let fingerprint = parts.joined(separator: "§")
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
