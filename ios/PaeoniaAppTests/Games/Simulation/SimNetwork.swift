import Foundation
@testable import PaeoniaApp

/// One phone's connection to the fake server, with the faults the driver turns on.
///
/// Every call yields first, so it is asynchronous like a real request. Offline,
/// it fails as `URLSession` does. Otherwise the fault plan may drop it before
/// the server sees it, drop the answer after the server applied it, refuse it
/// with a bare "Server Error", or hold it until the driver lets it go. A call
/// that is still on its way when the app is force quit never answers that app.
@MainActor
final class SimNetwork {
    enum Fault: String {
        case none
        case dropBefore
        case dropAfter
        case serverError
        case hold
    }

    /// How a held call ends when the driver lets it go.
    enum Release {
        case deliver
        case dropBefore
        case dropAfter
    }

    private final class HeldCall {
        let name: String
        var continuation: CheckedContinuation<Release, Never>?

        init(name: String) {
            self.name = name
        }
    }

    let name: String
    private let log: SimLog
    private var random: SimRandom
    var isOnline = true
    /// Faults are drawn only while this is on. The driver turns it off to settle.
    var faultsEnabled = true
    var dropRate = 0.04
    var serverErrorRate = 0.01
    var holdRate = 0.04
    /// Bumped by a force quit. A call started by an older app never answers.
    private(set) var incarnation = 0
    private var held: [HeldCall] = []
    /// Calls between their start and their answer, held ones included.
    private(set) var inFlight = 0
    private(set) var callCount = 0

    init(name: String, log: SimLog, random: SimRandom) {
        self.name = name
        self.log = log
        self.random = random
    }

    var heldCount: Int {
        held.count
    }

    func killApp() {
        incarnation += 1
    }

    /// Lets the oldest held calls go, each with an ending drawn from the plan.
    func releaseHeld(count: Int? = nil, deliverAll: Bool = false) {
        let releasing = Array(held.prefix(count ?? held.count))
        held.removeFirst(releasing.count)
        for call in releasing {
            let release: Release = deliverAll ? .deliver : random.weighted([(.deliver, 6), (.dropBefore, 1), (.dropAfter, 1)])
            log.add("\(name) net release \(call.name) \(release)")
            call.continuation?.resume(returning: release)
        }
    }

    private var scriptedFaults: [String: [Fault]] = [:]

    /// The next call named `callName` gets `fault`, whatever the plan says.
    func failNext(_ callName: String, with fault: Fault) {
        scriptedFaults[callName, default: []].append(fault)
    }

    private func drawFault(for callName: String) -> Fault {
        if var scripted = scriptedFaults[callName], !scripted.isEmpty {
            let fault = scripted.removeFirst()
            scriptedFaults[callName] = scripted
            return fault
        }
        guard faultsEnabled else { return .none }
        // Presence is a fire-and-forget heartbeat. Holding it would only delay
        // the next one, so it only drops.
        let canHold = callName != "presence"
        return random.weighted([
            (.none, 1 - dropRate * 2 - serverErrorRate - (canHold ? holdRate : 0)),
            (.dropBefore, dropRate),
            (.dropAfter, dropRate),
            (.serverError, serverErrorRate),
            (.hold, canHold ? holdRate : 0),
        ])
    }

    /// - Parameter started: The incarnation of the app that makes the call.
    func call<T>(_ callName: String, from started: Int, apply: () throws -> T) async throws -> T {
        guard started == incarnation else { throw CancellationError() }
        callCount += 1
        inFlight += 1
        defer { inFlight -= 1 }
        await Task.yield()
        guard isOnline else { throw URLError(.notConnectedToInternet) }
        var fault = drawFault(for: callName)
        if fault == .hold {
            log.add("\(name) net hold \(callName)")
            let call = HeldCall(name: callName)
            let release = await withCheckedContinuation { continuation in
                call.continuation = continuation
                held.append(call)
            }
            switch release {
            case .deliver: fault = .none
            case .dropBefore: fault = .dropBefore
            case .dropAfter: fault = .dropAfter
            }
            guard isOnline || fault == .dropAfter else { throw URLError(.networkConnectionLost) }
        }
        switch fault {
        case .dropBefore:
            log.add("\(name) net dropBefore \(callName)")
            throw URLError(.networkConnectionLost)
        case .serverError:
            log.add("\(name) net serverError \(callName)")
            throw PaeoniaConvexError.server(code: nil, message: "[Request ID: sim] Server Error")
        case .none, .dropAfter, .hold:
            break
        }
        let result: T
        do {
            result = try apply()
        } catch {
            log.add("\(name) \(callName) refused: \(error)")
            throw error
        }
        if ["pick", "submitDrawing", "guess", "giveUp", "reaction", "resultSeen", "upload", "submitPart", "revealSeen", "star"].contains(callName) {
            log.add("\(name) \(callName) applied")
        }
        if fault == .dropAfter {
            log.add("\(name) net dropAfter \(callName)")
            throw URLError(.networkConnectionLost)
        }
        // The app that sent it is gone, so nobody reads the answer.
        guard started == incarnation else { throw CancellationError() }
        return result
    }
}

/// `DrawAndGuessGateway` for one person, through their phone's network.
final class SimGateway: DrawAndGuessGateway, @unchecked Sendable {
    private let user: UUID
    private let server: SimServer
    private let network: SimNetwork
    private let incarnation: Int

    @MainActor
    init(user: UUID, server: SimServer, network: SimNetwork) {
        self.user = user
        self.server = server
        self.network = network
        incarnation = network.incarnation
    }

    @MainActor
    private func call<T>(_ name: String, _ apply: @MainActor (SimServer, UUID) throws -> T) async throws -> T {
        try await network.call(name, from: incarnation) { try apply(server, user) }
    }

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings {
        try await call("setSettings") { $0.setSettings(user: $1, playStyle: playStyle, language: language) }
    }

    func ensureDrawAndGuessGame() async throws -> RemoteEnsureGameResult {
        try await call("ensure") { try $0.ensureGame(user: $1) }
    }

    func loadDrawAndGuess() async throws -> RemoteDrawAndGuessState {
        try await call("load") { $0.view(for: $1) }
    }

    func loadDrawAndGuessRound(roundID: UUID) async throws -> RemoteDrawAndGuessRound? {
        try await call("loadRound") { $0.round(roundID, for: $1) }
    }

    func pickWord(_ pick: GamePickWordPayload, operation: SyncClientOperation) async throws -> RemotePickedWord {
        try await call("pick") { try $0.pickWord(user: $1, pick, operation: operation) }
    }

    func submitDrawing(
        roundID: UUID,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> RemoteSubmitDrawingResult {
        try await call("submitDrawing") {
            try $0.submitDrawing(user: $1, roundID: roundID, assetID: mediaAssetID, operation: operation)
        }
    }

    func markRoundSeen(roundID: UUID) async throws -> RemoteMarkSeenResult {
        try await call("markSeen") { try $0.markSeen(user: $1, roundID: roundID) }
    }

    func submitGuess( // swiftlint:disable:this function_parameter_count
        roundID: UUID,
        guess: String,
        speedBonus: Int?,
        solveMs: Int?,
        hintsUsed: Int?,
        operation: SyncClientOperation
    ) async throws -> RemoteGuessResult {
        try await call("guess") {
            try $0.submitGuess(
                user: $1,
                roundID: roundID,
                guess: guess,
                speedBonus: speedBonus,
                solveMs: solveMs,
                hintsUsed: hintsUsed,
                operation: operation
            )
        }
    }

    func giveUp(roundID: UUID, operation: SyncClientOperation) async throws -> RemoteGiveUpResult {
        try await call("giveUp") { try $0.giveUp(user: $1, roundID: roundID, operation: operation) }
    }

    func setRoundReaction(roundID: UUID, reaction: DrawAndGuessReaction?) async throws -> RemoteReactionResult {
        try await call("reaction") { try $0.setReaction(user: $1, roundID: roundID, reaction: reaction) }
    }

    func markRoundResultSeen(roundID: UUID) async throws -> RemoteResultSeenResult {
        try await call("resultSeen") { try $0.markResultSeen(user: $1, roundID: roundID) }
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        try await call("overview") { RemoteGamesOverview(drawAndGuess: $0.view(for: $1)) }
    }

    func sendInvite(_: GameKind) async throws -> RemoteInviteResult {
        try await call("invite") { try $0.sendInvite(user: $1) }
    }

    /// The relay ticket. It changes nothing on the server.
    func fetchLiveTicket() async throws {
        try await call("ticket") { _, _ in () }
    }

    func setPresence(_: GameKind, isPresent: Bool) async throws {
        try await call("presence") { $0.setPresence(user: $1, present: isPresent) }
    }

    // The simulation plays rounds. "Our drawings" has its own tests, so these stay offline.

    func loadDrawAndGuessHistory(
        starredOnly _: Bool,
        beforeRoundNumber _: Int?,
        limit _: Int
    ) async throws -> RemoteDrawAndGuessHistoryPage {
        throw URLError(.notConnectedToInternet)
    }

    func loadDrawAndGuessRecords() async throws -> RemoteDrawAndGuessRecords {
        throw URLError(.notConnectedToInternet)
    }

    func setRoundStar(roundID _: UUID, starred _: Bool) async throws -> RemoteRoundStarResult {
        throw URLError(.notConnectedToInternet)
    }
}

/// Drawing uploads and downloads through the phone's network.
final class SimDrawingTransfer: GameDrawingTransferring, @unchecked Sendable {
    private let user: UUID
    private let server: SimServer
    private let network: SimNetwork
    private let incarnation: Int

    @MainActor
    init(user: UUID, server: SimServer, network: SimNetwork) {
        self.user = user
        self.server = server
        self.network = network
        incarnation = network.incarnation
    }

    func uploadDrawing(
        _ data: Data,
        parent: GameUploadParent,
        coupleID _: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
        try await upload(data, roundID: parent.id, reserveOperation: reserveOperation)
    }

    @MainActor
    private func upload(_ data: Data, roundID: UUID, reserveOperation: SyncClientOperation) async throws -> UUID {
        try await network.call("upload", from: incarnation) {
            try server.uploadDrawing(user: user, data: data, roundID: roundID, reserveOperation: reserveOperation)
        }
    }

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data {
        try await download(mediaAssetID)
    }

    @MainActor
    private func download(_ assetID: UUID) async throws -> Data {
        try await network.call("download", from: incarnation) { try server.download(assetID: assetID) }
    }
}
