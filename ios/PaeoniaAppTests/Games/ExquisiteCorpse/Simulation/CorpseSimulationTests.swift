import Foundation
import Testing
@testable import PaeoniaApp

/// Two phones play Exquisite corpse against the in-memory server with faults, and
/// the invariants in `CorpseSimDriver+Invariants` are checked whenever the network
/// is up and the queues have drained. A failure prints its seed and the action log.
///
/// Run more seeds locally with `TEST_RUNNER_CORPSE_SIM_SEEDS=200` (xcodebuild passes
/// `TEST_RUNNER_` variables to the test process without the prefix), start elsewhere
/// with `TEST_RUNNER_CORPSE_SIM_FIRST_SEED`, and replay one seed with
/// `TEST_RUNNER_CORPSE_SIM_SEED`. `TEST_RUNNER_CORPSE_SIM_STEPS` sets the steps per
/// seed, `TEST_RUNNER_CORPSE_SIM_FAULT_SCALE` multiplies the network fault rates, and
/// `TEST_RUNNER_CORPSE_SIM_CHAOS_PERCENT` sets how many steps the world acts in.
/// Reports go to `/tmp/corpse-sim.log`.
@MainActor
@Suite(.serialized)
struct CorpseSimulationTests {
    /// Seeds in the default run. Keep the run well under a minute.
    static let defaultSeedCount = 4
    static let reportPath = "/tmp/corpse-sim.log"

    private static func environmentNumber(_ name: String) -> UInt64? {
        ProcessInfo.processInfo.environment[name].flatMap(UInt64.init)
    }

    private static func seeds() -> [UInt64] {
        if let only = environmentNumber("CORPSE_SIM_SEED") {
            return [only]
        }
        let first = environmentNumber("CORPSE_SIM_FIRST_SEED") ?? 1
        let count = environmentNumber("CORPSE_SIM_SEEDS") ?? UInt64(defaultSeedCount)
        return Array(first..<(first + count))
    }

    private static func config() -> CorpseSimDriver.Config {
        var config = CorpseSimDriver.Config()
        if let steps = environmentNumber("CORPSE_SIM_STEPS") {
            config.steps = Int(steps)
        }
        if let faults = environmentNumber("CORPSE_SIM_FAULT_SCALE") {
            config.faultScale = Double(faults)
        }
        if let chaos = environmentNumber("CORPSE_SIM_CHAOS_PERCENT") {
            config.chaosRate = Double(chaos) / 100
        }
        return config
    }

    @Test func twoPhonesDrawManySeededFigures() async {
        let seeds = Self.seeds()
        let failures = await SimReport.play(seeds) { await Self.draw(seed: $0) }
        SimReport.write("ran \(seeds.count) seeds, \(failures) failed", to: Self.reportPath)
    }

    /// Plays one seed and returns whether it passed.
    private static func draw(seed: UInt64) async -> Bool {
        let config = Self.config()
        let driver = CorpseSimDriver(seed: seed, config: config)
        do {
            try await SimReport.run(timeout: .seconds(Double(config.steps) * 0.8)) { try await driver.run() }
            SimReport.write(await driver.summary(), to: reportPath)
            if ProcessInfo.processInfo.environment["CORPSE_SIM_DUMP"] != nil {
                SimReport.write(driver.log.tail(100_000), to: reportPath)
            }
            return true
        } catch {
            SimReport.write(
                "FAILED seed \(seed): \(error)\n\(driver.log.tail())\n\(await driver.ledgerDump())",
                to: reportPath
            )
            Issue.record("""
            Exquisite corpse simulation failed with seed \(seed): \(error)
            Replay with TEST_RUNNER_CORPSE_SIM_SEED=\(seed). Log:
            \(driver.log.tail())
            """)
            return false
        }
    }
}
