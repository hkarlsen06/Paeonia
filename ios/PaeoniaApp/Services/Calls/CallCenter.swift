import Observation
import UIKit

/// What the call screens can ask the call engine to do. `CallEngine` is the real one. Developer
/// scenarios use one that does nothing and set `CallCenter.session` themselves.
@MainActor
protocol CallEngineActions: AnyObject {
    /// Starts a voice call to the partner. The engine moves `session` through its phases and
    /// ends it with a failure it can name.
    func startCall()
    func answer()
    func decline()
    func end()
    func setMuted(_ isMuted: Bool)
    /// Moves the sound between the earpiece and the speaker. With AirPods or a car connected,
    /// the call screen shows the system route picker instead.
    func toggleSpeaker()
    func setCameraOn(_ isOn: Bool)
    func flipCamera()
    /// The partner's time zone for the night check, or nil when it is not known.
    func partnerTimeZone() async -> TimeZone?
    /// Reads the partner and their time zone again in the background, so a call can start and
    /// ring without waiting for them.
    func refreshCallContext()
    /// A view that shows one side's video. The engine keeps it current while the call runs.
    func makeVideoView(_ source: CallVideoSource) -> UIView
}

/// The live call for the whole app. The call screen, the bubble and the call buttons read it from
/// the environment. Only the engine changes `session`.
@MainActor
@Observable
final class CallCenter {
    var session: CallSession? {
        didSet {
            let usesProximitySensor = session?.usesProximitySensor ?? false
            if UIDevice.current.isProximityMonitoringEnabled != usesProximitySensor {
                UIDevice.current.isProximityMonitoringEnabled = usesProximitySensor
            }
        }
    }
    var presentation: CallPresentation = .full
    @ObservationIgnored let engine: any CallEngineActions

    init(engine: any CallEngineActions, session: CallSession? = nil) {
        self.engine = engine
        self.session = session
    }

    /// True while a call rings out, connects or runs, so a second call cannot start.
    var isInCall: Bool {
        guard let session else {
            return false
        }
        if case .ended = session.phase {
            return false
        }
        return true
    }
}
