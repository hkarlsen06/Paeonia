import Foundation

/// Sends this phone's `LocationDeviceState` to the server, one report at a
/// time. A state the server already confirmed in this launch is not sent
/// again, and a failed report is sent at the next `report()`.
@MainActor
final class LocationDeviceStateReporter {
    /// The state to send now, or `nil` when nothing should be sent.
    var currentState: @MainActor () -> LocationDeviceState? = { nil }
    /// Gets the state that was sent and the choice the server kept. Returns
    /// the state the server now holds, or `nil` to send again next time.
    var handleAnswer: @MainActor (LocationDeviceState, Bool) -> LocationDeviceState? = { state, _ in state }

    private var gateway: LiveLocationGateway?
    private var task: Task<Void, Never>?
    private var reportsAgain = false
    private var lastConfirmed: LocationDeviceState?

    func report() {
        guard task == nil else {
            reportsAgain = true
            return
        }
        guard let state = currentState(), state != lastConfirmed, let gateway = makeGateway() else {
            return
        }
        task = Task {
            if let kept = try? await gateway.reportDeviceState(state, reportedAt: Date()) {
                lastConfirmed = handleAnswer(state, kept)
            }
            task = nil
            if reportsAgain {
                reportsAgain = false
                report()
            }
        }
    }

    /// Called when local data is cleared, so the next sign-in reports again.
    func forget() {
        lastConfirmed = nil
    }

    private func makeGateway() -> LiveLocationGateway? {
        if let gateway {
            return gateway
        }
        let made = (try? PaeoniaConvexClientProvider.shared.client()).map { LiveLocationGateway(client: $0) }
        gateway = made
        return made
    }
}
