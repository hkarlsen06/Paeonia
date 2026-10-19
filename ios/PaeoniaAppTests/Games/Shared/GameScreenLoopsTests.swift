import Foundation
import Testing
@testable import PaeoniaApp

/// A gateway whose "here" writes wait until the test lets them finish, so a
/// test can put a heartbeat on its way when the screen closes.
private final class HeldPresenceGateway: GamesGateway, @unchecked Sendable {
    struct Unused: Error {}

    private let lock = NSLock()
    private var startedWrites: [Bool] = []
    private var finishedWrites: [Bool] = []
    private var isReleased = false

    var started: [Bool] { lock.withLock { startedWrites } }
    var finished: [Bool] { lock.withLock { finishedWrites } }

    func release() {
        lock.withLock { isReleased = true }
    }

    func setPresence(_: GameKind, isPresent: Bool) async throws {
        lock.withLock { startedWrites.append(isPresent) }
        while isPresent, !lock.withLock({ isReleased }) {
            try await Task.sleep(for: .milliseconds(2))
        }
        lock.withLock { finishedWrites.append(isPresent) }
    }

    // swiftlint:disable async_without_await
    func setSettings(playStyle _: GamePlayStyle, language _: GameLanguage) async throws -> RemoteGameSettings {
        throw Unused()
    }

    func loadOverview() async throws -> RemoteGamesOverview {
        throw Unused()
    }

    func sendInvite(_: GameKind) async throws -> RemoteInviteResult {
        throw Unused()
    }
    // swiftlint:enable async_without_await
}

/// The loops every game screen shares.
@MainActor
struct GameScreenLoopsTests {
    private let gateway = HeldPresenceGateway()

    private func makeLoops() -> GameScreenLoops {
        GameScreenLoops(
            kind: .mindMeld,
            gateway: gateway,
            heartbeatInterval: .seconds(3_600),
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    @Test func theLeavingWriteWaitsForAHeartbeatThatIsStillOnItsWay() async {
        let loops = makeLoops()
        loops.beginHeartbeat()
        #expect(await waitUntil { gateway.started == [true] })

        loops.endHeartbeat()
        // The leaving write would have gone out by now if it did not wait.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(gateway.started == [true])

        gateway.release()
        #expect(await waitUntil { gateway.finished == [true, false] })
    }

    @Test func leavingAndComingBackWritesInThatOrder() async {
        let loops = makeLoops()
        gateway.release()
        loops.beginHeartbeat()
        #expect(await waitUntil { gateway.finished == [true] })

        loops.endHeartbeat()
        loops.beginHeartbeat()

        #expect(await waitUntil { gateway.finished == [true, false, true] })
        loops.endHeartbeat()
    }
}
