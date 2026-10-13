import Foundation
import Testing
@testable import PaeoniaApp

/// Two phones play Draw & Guess against the in-memory server with faults, and
/// the invariants in `SimDriver` are checked whenever the network is up and the
/// queues have drained. A failure prints its seed and the action log.
///
/// Run more seeds locally with `TEST_RUNNER_DNG_SIM_SEEDS=500` (xcodebuild passes
/// `TEST_RUNNER_` variables to the test process without the prefix), start
/// elsewhere with `TEST_RUNNER_DNG_SIM_FIRST_SEED`, and replay one seed with
/// `TEST_RUNNER_DNG_SIM_SEED`. `TEST_RUNNER_DNG_SIM_STEPS` sets the steps per seed, and
/// `TEST_RUNNER_DNG_SIM_FAULT_SCALE` multiplies the network fault rates, and
/// `TEST_RUNNER_DNG_SIM_CHAOS_PERCENT` sets how many steps the world acts in.
@MainActor
@Suite(.serialized)
struct DrawAndGuessSimulationTests {
    /// Seeds in the default run. Keep the run under a couple of minutes.
    static let defaultSeedCount = 6

    private static func environmentNumber(_ name: String) -> UInt64? {
        ProcessInfo.processInfo.environment[name].flatMap(UInt64.init)
    }

    @Test func twoPhonesPlayManySeededGames() async {
        let seeds: [UInt64]
        if let only = Self.environmentNumber("DNG_SIM_SEED") {
            seeds = [only]
        } else {
            let first = Self.environmentNumber("DNG_SIM_FIRST_SEED") ?? 1
            let count = Self.environmentNumber("DNG_SIM_SEEDS") ?? UInt64(Self.defaultSeedCount)
            seeds = Array(first..<(first + count))
        }
        var failures = 0
        for seed in seeds {
            var config = SimDriver.Config()
            if let steps = Self.environmentNumber("DNG_SIM_STEPS") {
                config.steps = Int(steps)
            }
            if let faults = Self.environmentNumber("DNG_SIM_FAULT_SCALE") {
                config.faultScale = Double(faults)
            }
            if let chaos = Self.environmentNumber("DNG_SIM_CHAOS_PERCENT") {
                config.chaosRate = Double(chaos) / 100
            }
            let driver = SimDriver(seed: seed, config: config)
            do {
                try await SimReport.run(timeout: .seconds(Double(config.steps) * 0.6)) { try await driver.run() }
                SimReport.write(await driver.summary())
                if ProcessInfo.processInfo.environment["DNG_SIM_DUMP"] != nil {
                    SimReport.write(driver.log.tail(100_000))
                }
            } catch {
                failures += 1
                SimReport.write("FAILED seed \(seed): \(error)\n\(driver.log.tail())\n\(await driver.ledgerDump())")
                Issue.record("""
                Draw & Guess simulation failed with seed \(seed): \(error)
                Replay with TEST_RUNNER_DNG_SIM_SEED=\(seed). Log:
                \(driver.log.tail())
                """)
                if failures >= 3 { break }
            }
        }
        SimReport.write("ran \(seeds.count) seeds, \(failures) failed")
    }
}
