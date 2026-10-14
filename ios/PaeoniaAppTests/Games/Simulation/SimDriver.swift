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
    private var random: SimRandom

    /// Strokes on each phone's board for a round, as the person drew them.
    var boardStrokes: [String: (roundID: UUID, count: Int)] = [:]
    var settlesWithoutProgress = 0
    var lastProgressVersion = -1
    private var lastHeartbeat: Date
    private var hasWeekPassed = false
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
    private var isBurst = false

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
            parts.append("\(phone.name): launches \(phone.launchCount) moves \(ledger.count) dropped \(terminal) notices \(phone.notices.count) calls \(phone.network.callCount)")
        }
        return parts.joined(separator: ", ")
    }

    private(set) var settleCount = 0

    /// Every write each phone queued and how it ended, for a failure report.
    func ledgerDump() async -> String {
        var lines: [String] = []
        struct Round: Decodable { let roundID: UUID }
        for phone in phones {
            for entry in await phone.pending.ledger {
                let round = entry.requestData.flatMap { try? JSONDecoder().decode(Round.self, from: $0) }
                lines.append("\(phone.name) \(entry.kind.rawValue) round \(round?.roundID.uuidString.prefix(6) ?? "-") op \(entry.operationID.uuidString.prefix(6)) -> \(entry.outcome)")
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
        first.games?.draftPlayStyle = random.chance(0.5) ? .against : .together
        first.games?.draftLanguage = random.chance(0.7) ? .en : .nb
        log.add("\(first.name) setup \(first.games?.draftPlayStyle.rawValue ?? "") \(first.games?.draftLanguage.rawValue ?? "")")
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
            await chaos(on: phone)
        }
    }

    /// What the world does: networks, the app's life, the relay, the clock.
    private func chaos(on phone: SimPhone) async {
        enum Chaos: CaseIterable {
            case offline, online, background, foreground, closeScreen, forceQuit, dropSocket, reconnect
            case reapGhosts, feedOutage, feedDelay, releaseHeld, smallTime, mediumTime, bigTime
            case changeLanguage, retrySync, weekPasses
        }
        let chaos = random.weighted([
            (Chaos.offline, phone.network.isOnline ? 4 : 0),
            (.online, phone.network.isOnline ? 0 : 8),
            (.background, phone.isForeground ? 3 : 0),
            (.foreground, phone.isForeground ? 0 : 6),
            (.closeScreen, 2),
            (.forceQuit, 1.5),
            (.dropSocket, 2),
            (.reconnect, 5),
            (.reapGhosts, 2),
            (.feedOutage, 1.5),
            (.feedDelay, 1.5),
            (.releaseHeld, phone.network.heldCount > 0 ? 6 : 0),
            (.smallTime, 6),
            (.mediumTime, 3),
            (.bigTime, 0.6),
            (.changeLanguage, 0.8),
            (.retrySync, 3),
            (.weekPasses, hasWeekPassed ? 0 : 0.25),
        ])
        switch chaos {
        case .offline: phone.setOnline(false)
        case .online: phone.setOnline(true)
        case .background: phone.moveToBackground()
        case .foreground: phone.moveToForeground()
        case .closeScreen: phone.closeScreen()
        case .forceQuit: phone.forceQuit(closesSocket: random.chance(0.6))
        case .dropSocket:
            log.add("\(phone.name) socket drop")
            phone.socket?.dropSilently()
        case .reconnect: phone.reconnectRelay()
        case .reapGhosts: relay.reapGhosts()
        case .feedOutage:
            phone.isFeedOutage.toggle()
            log.add("\(phone.name) feed outage \(phone.isFeedOutage)")
        case .feedDelay:
            phone.isFeedDelayed.toggle()
            log.add("\(phone.name) feed delayed \(phone.isFeedDelayed)")
        case .releaseHeld: phone.network.releaseHeld(count: random.int(1...max(1, phone.network.heldCount)))
        case .smallTime: advanceTime(Double(random.int(1...6)))
        case .mediumTime: advanceTime(Double(random.int(20...45)))
        case .bigTime: advanceTime(Double(random.int(120...900)))
        case .changeLanguage:
            guard let games = phone.games, let settings = server.settings else { return }
            let language: GameLanguage = settings.language == .en ? .nb : .en
            log.add("\(phone.name) change language to \(language.rawValue)")
            let style: GamePlayStyle = random.chance(0.5) ? .against : .together
            Task { await games.saveSettings(playStyle: style, language: language) }
        case .weekPasses:
            // Only once a run: the app renews a gone upload at most once a day of real time.
            hasWeekPassed = true
            advanceTime(8 * 86_400)
            log.add("server swept \(server.sweepOrphanedUploads()) unused uploads")
        case .retrySync:
            log.add("\(phone.name) retry timer")
            Task { await phone.sync() }
        }
    }

    private func advanceTime(_ seconds: TimeInterval) {
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

    // MARK: - The person

    private func act(as phone: SimPhone) async {
        guard phone.isAlive else {
            phone.launch()
            return
        }
        guard phone.isForeground else {
            phone.moveToForeground()
            return
        }
        guard phone.isScreenOpen, let viewModel = phone.viewModel else {
            if random.chance(0.15), let games = phone.games {
                log.add("\(phone.name) hub refresh")
                Task { await games.refresh() }
            } else {
                phone.openScreen()
            }
            return
        }
        switch viewModel.phase {
        case .chooseWord:
            await chooseWord(phone, viewModel)
        case .drawing:
            await draw(phone, viewModel)
        case .waitingForDrawing, .watchingLive, .guessing:
            await guess(phone, viewModel)
        case .reveal:
            await reveal(phone, viewModel)
        case .waitingForGuess, .waitingForWord:
            if viewModel.invite == .available, random.chance(0.15) {
                log.add("\(phone.name) invite")
                Task { await viewModel.sendInvite() }
            } else if random.chance(0.2) {
                phone.closeScreen()
            }
        case .waitingToSync:
            log.add("\(phone.name) try again")
            Task { await viewModel.retrySending() }
        case .needsSetup:
            if let games = phone.games {
                Task { await games.finishSetup() }
            }
        case .loading, .preparing:
            if viewModel.startFailed {
                Task { await viewModel.retryStart() }
            }
        }
    }

    private func expectMove(
        _ phone: SimPhone,
        kind: SyncPendingOperationKind,
        _ action: String,
        shows expected: Set<DrawAndGuessPhase> = [],
        _ body: () async -> Void
    ) async {
        guard !isBurst else {
            await body()
            return
        }
        let before = await phone.pending.ledger.filter { $0.kind == kind }.count
        let noticesBefore = phone.notices.count
        await body()
        await pump()
        let after = await phone.pending.ledger.filter { $0.kind == kind }.count
        if after == before {
            let noticed = phone.notices.dropFirst(noticesBefore).contains { $0 == .couldNotSaveMove || $0 == .drawingTooBig }
            if !noticed {
                failNow("\(phone.name) \(action) made no move and showed no notice")
            }
            return
        }
        // Local first: the screen shows the move at once, online or not.
        if !expected.isEmpty, phone.notices.count == noticesBefore, let phase = phone.activeViewModel?.phase,
           !expected.contains(phase) {
            failNow("\(phone.name) \(action) left the screen in \(phase), expected \(expected)")
        }
    }

    var pendingFailure: SimFailure?

    private func failNow(_ message: String) {
        if pendingFailure == nil {
            pendingFailure = SimFailure(message: message)
        }
    }

    private func chooseWord(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        if !viewModel.choices.isEmpty, random.chance(0.85) {
            let choice = random.pick(viewModel.choices)
            log.add("\(phone.name) pick \(choice.word) (\(choice.difficulty.rawValue))")
            await expectMove(phone, kind: .pickDrawWord, "pick", shows: [.drawing]) { await viewModel.chooseWord(choice) }
        } else {
            let custom = random.pick(["flying cat", "  Dog At   Mom ", "Brunost", "ab", "Æ Ø Å", "hot dog", "vaffel jern"])
            viewModel.customWord = custom
            guard viewModel.customWordValidation.word != nil else { return }
            log.add("\(phone.name) pick custom '\(custom)'")
            await expectMove(phone, kind: .pickDrawWord, "custom pick", shows: [.drawing]) { await viewModel.chooseCustomWord() }
        }
    }

    private func draw(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        phone.updateScreens()
        guard let canvas = phone.canvas, let round = viewModel.round else { return }
        let board = viewModel.board
        if !board.isEmpty, random.chance(0.35), viewModel.canFinishDrawing {
            log.add("\(phone.name) done (\(board.drawing.strokes.count) strokes)")
            await expectMove(phone, kind: .submitGameDrawing, "done", shows: [.waitingForGuess, .reveal]) { await viewModel.finishDrawing() }
            boardStrokes[phone.name] = nil
            drawnHere.insert(round.id)
            return
        }
        if !board.isEmpty, random.chance(0.06) {
            log.add("\(phone.name) erase a stroke")
            canvas.erase(strokeAt: random.int(0...(board.drawing.strokes.count - 1)))
        } else if !board.isEmpty, random.chance(0.03) {
            log.add("\(phone.name) clear")
            board.clear()
            canvas.sync()
        } else {
            let count = random.int(1...3)
            for _ in 0..<count {
                canvas.draw(SimStrokes.stroke(seed: &random, side: canvas.side))
            }
            log.add("\(phone.name) draw \(count) strokes")
        }
        boardStrokes[phone.name] = (round.id, board.drawing.strokes.count)
    }

    private func guess(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        guard !viewModel.isShowingWrongGuess, let round = viewModel.round else { return }
        let canSee = viewModel.phase != .waitingForDrawing
        let action = random.weighted([
            ("right", canSee ? 3.0 : 0.5),
            ("wrong", 4.5),
            ("showMe", 0.6),
            ("hint", viewModel.canShowLetter ? 1.2 : 0),
            ("wait", 1.5),
        ])
        switch action {
        case "right", "wrong":
            if viewModel.slots.slots.contains(where: { $0.tile != nil && !$0.isHint }) {
                viewModel.clearGuess()
            }
            let tiles = viewModel.tiles
            // A hint locks its slot, so the person fills only the open ones.
            let open = viewModel.slots.slots.filter { !$0.isGap && $0.tile == nil }
            guard !tiles.isEmpty, !open.isEmpty else { return }
            var used = viewModel.slots.placedTileIDs
            var letters: [DrawAndGuessTile] = []
            if action == "right" {
                for slot in open {
                    let letter = Array(viewModel.slots.answer)[slot.id]
                    guard let tile = tiles.first(where: { $0.letter == letter && !used.contains($0.id) }) else { return }
                    used.insert(tile.id)
                    letters.append(tile)
                }
            } else {
                var pool = tiles.filter { !used.contains($0.id) }
                for _ in open {
                    let index = random.int(0...(pool.count - 1))
                    letters.append(pool.remove(at: index))
                }
            }
            // The whole word as it will stand, hinted letters included.
            var standing = viewModel.slots.slots.map { $0.isGap ? Character(" ") : ($0.tile?.letter ?? "?") }
            for (slot, tile) in zip(open, letters) {
                standing[slot.id] = tile.letter
            }
            let word = String(standing)
            let isRight = word == viewModel.slots.answer
            if isRight {
                let claim = viewModel.speedBonusClaim(at: clock.now)
                promisedBonus[round.id] = claim.speedBonus
                promisedHints[round.id] = claim.hintsUsed
            }
            log.add("\(phone.name) guess \(word) on \(round.id.uuidString.prefix(6)) [\(viewModel.phase)]")
            await expectMove(phone, kind: .submitGameGuess, "guess", shows: isRight ? [.reveal] : []) {
                for tile in letters {
                    viewModel.placeTile(tile)
                }
            }
        case "hint":
            viewModel.showLetter()
            hinted["\(phone.name)-\(round.id)"] = viewModel.slots.hintedIndexes
            log.add("\(phone.name) hint \(viewModel.slots.hintedIndexes) on \(round.id.uuidString.prefix(6))")
        case "showMe":
            log.add("\(phone.name) show me")
            await expectMove(phone, kind: .giveUpGameRound, "show me", shows: [.reveal]) { await viewModel.giveUp() }
        default:
            if random.chance(0.3) {
                viewModel.setFastForward(true)
                viewModel.setFastForward(false)
            }
        }
    }

    private func reveal(_ phone: SimPhone, _ viewModel: DrawAndGuessViewModel) async {
        if let round = viewModel.round, round.guesserUserID == phone.userID, random.chance(0.35) {
            let reaction = random.pick(DrawAndGuessReaction.allCases)
            log.add("\(phone.name) react \(reaction.rawValue)")
            await expectMove(phone, kind: .setGameRoundReaction, "react") { await viewModel.react(reaction) }
            shownReactions[round.id, default: []].insert(viewModel.reveal?.reaction?.rawValue ?? "none")
            return
        } else {
            log.add("\(phone.name) continue")
            let roundID = viewModel.round?.id
            Task { await viewModel.continueFromReveal() }
            guard !isBurst else { return }
            await pump()
            if phone.activeViewModel === viewModel, viewModel.phase == .reveal, viewModel.round?.id == roundID {
                failNow("\(phone.name) continue did not leave the reveal")
            }
        }
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
