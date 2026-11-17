import XCTest

/// Turns the simulator for `scripts/scenario-screenshot --ipad`, because simctl has no command for it
/// and an iPad app can't turn its own window. The turn outlasts the test. It runs only when the script
/// sets `TEST_RUNNER_PAEONIA_SIMULATOR_ORIENTATION` to `portrait` or `landscape`.
final class SimulatorOrientation: XCTestCase {
    @MainActor
    func testTurn() throws {
        let wanted = ProcessInfo.processInfo.environment["PAEONIA_SIMULATOR_ORIENTATION"]
        try XCTSkipIf(wanted == nil, "Only scripts/scenario-screenshot turns the simulator.")
        let orientation: UIDeviceOrientation = wanted == "landscape" ? .landscapeRight : .portrait
        XCUIDevice.shared.orientation = orientation
        XCTAssertEqual(XCUIDevice.shared.orientation, orientation)
    }
}
