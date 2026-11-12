import Foundation
import Synchronization
import Testing
@testable import PaeoniaApp

/// A sign-in that ends must reach the server, at once and once more after a registration that was
/// on its way could have landed, and no registration may wait for it.
@MainActor
struct LiveActivityInstallRegistryTests {
    private let server = FakeLiveActivityTokenServer()
    private let clock = TestClock()
    private let registry: LiveActivityInstallRegistry

    init() {
        registry = LiveActivityInstallRegistry(
            store: InMemoryLiveActivityInstallStore(),
            server: server,
            now: clock.now
        )
    }

    @Test func aNewSignInRegistersWhileTheOldInstallsEndStillFails() async throws {
        _ = try await registry.register(.start, token: "token", activityID: nil, for: "account")
        let first = try #require(server.liveInstalls.first)
        try registry.endInstall()
        server.failsEnds = true
        await #expect(throws: (any Error).self) { _ = try await registry.sendEnds() }

        _ = try await registry.register(.start, token: "token", activityID: nil, for: "account")

        // The server keeps one row per token, so the new install took it over.
        #expect(server.liveInstalls.count == 1)
        #expect(server.liveInstalls.first != first)
        server.failsEnds = false
        _ = try await registry.sendEnds()
        #expect(server.endedInstalls == [first])
    }

    @Test func anEndGoesOutAtOnceAndAgainAfterTheSettleTime() async throws {
        _ = try await registry.register(.start, token: "token", activityID: nil, for: "account")
        let install = try #require(server.liveInstalls.first)
        try registry.endInstall()

        let next = try await registry.sendEnds()
        #expect(server.liveInstalls.isEmpty)
        #expect(next == clock.now().addingTimeInterval(LiveActivityInstallRegistry.settleInterval))

        // A registration that was on its way during the sign-out lands after the first end.
        server.addToken(install: install)
        clock.advance(by: LiveActivityInstallRegistry.settleInterval)
        #expect(try await registry.sendEnds() == nil)
        #expect(server.liveInstalls.isEmpty)
    }

    @Test func aFailedEndStaysUntilASendGoesThrough() async throws {
        _ = try await registry.register(.start, token: "token", activityID: nil, for: "account")
        try registry.endInstall()
        clock.advance(by: LiveActivityInstallRegistry.settleInterval)
        server.failsEnds = true
        await #expect(throws: (any Error).self) { _ = try await registry.sendEnds() }
        #expect(!server.liveInstalls.isEmpty)

        server.failsEnds = false
        #expect(try await registry.sendEnds() == nil)
        #expect(server.liveInstalls.isEmpty)
    }

    @Test func anotherAccountEndsTheFirstAccountsInstall() async throws {
        _ = try await registry.register(.start, token: "first-token", activityID: nil, for: "first")
        let first = try #require(server.liveInstalls.first)
        _ = try await registry.register(.start, token: "second-token", activityID: nil, for: "second")
        _ = try await registry.sendEnds()

        #expect(server.endedInstalls == [first])
        #expect(server.liveInstalls.count == 1)
        #expect(try registry.accountID == "second")
    }

    @Test func anInstallTakenByAnotherAccountIsReplacedAndNotEnded() async throws {
        _ = try await registry.register(.start, token: "token", activityID: nil, for: "account")
        let taken = try #require(server.liveInstalls.first)
        server.takenInstalls = [taken]

        #expect(try await registry.register(.start, token: "token", activityID: nil, for: "account") == .saved)
        _ = try await registry.sendEnds()

        #expect(server.liveInstalls.count == 1)
        #expect(server.liveInstalls.first != taken)
        #expect(server.endedInstalls.isEmpty)
    }

    @Test func theSameSignInKeepsOneInstall() async throws {
        _ = try await registry.register(.start, token: "token", activityID: nil, for: "account")
        _ = try await registry.register(.update, token: "update", activityID: "activity", for: "account")

        #expect(server.liveInstalls.count == 1)
    }
}

/// Keeps what the server would: which installs hold tokens, and which installs it ended.
@MainActor
final class FakeLiveActivityTokenServer: LiveActivityTokenServer {
    private(set) var tokensByInstall: [String: Set<String>] = [:]
    private(set) var endedInstalls: [String] = []
    var failsEnds = false
    var takenInstalls: Set<String> = []

    var liveInstalls: [String] {
        tokensByInstall.filter { !$0.value.isEmpty }.keys.sorted()
    }

    func addToken(install: String, token: String = "late") {
        tokensByInstall[install, default: []].insert(token)
    }

    func register(_ registration: LiveActivityTokenRegistration) throws -> LiveActivityRegistrationResult {
        if takenInstalls.contains(registration.installID) {
            return .installTaken
        }
        // One row per token: a token that moved to another install leaves the old one.
        for install in tokensByInstall.keys {
            tokensByInstall[install]?.remove(registration.token)
        }
        addToken(install: registration.installID, token: registration.token)
        return registration.kind == .start ? .saved : .playing
    }

    func endInstall(_ installID: String) throws {
        if failsEnds {
            throw URLError(.notConnectedToInternet)
        }
        if tokensByInstall.removeValue(forKey: installID) != nil, !endedInstalls.contains(installID) {
            endedInstalls.append(installID)
        }
    }

    func endActivity(_: String, installID _: String) throws {}
}

final class InMemoryLiveActivityInstallStore: LiveActivityInstallStore {
    private let state = Mutex(LiveActivityInstallState())

    func load() -> LiveActivityInstallState {
        state.withLock { $0 }
    }

    func save(_ newState: LiveActivityInstallState) {
        state.withLock { $0 = newState }
    }
}

@MainActor
final class TestClock {
    private var current = Date(timeIntervalSince1970: 1_794_000_000)

    var now: () -> Date {
        { [unowned self] in current }
    }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }
}
