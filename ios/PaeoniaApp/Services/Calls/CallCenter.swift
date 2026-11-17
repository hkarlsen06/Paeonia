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
    /// Shows the system's screen sharing picker. Sharing starts once the person chooses there, and
    /// `CallSession.screenShare` says how the start goes. Nothing else can start a share.
    func startScreenShare()
    /// Ends this person's screen share, and the system's sharing indicator goes away.
    func stopScreenShare()
    /// Hides `CallSession.cameraOffSuggestion` for the rest of the call. The same reason does not
    /// come back, though the other reason can.
    func dismissCameraOffSuggestion()
    /// Zooms the back camera. `factor` counts the way `CallCameraZoom` does.
    func setBackCameraZoom(_ factor: Double)
    /// The partner's time zone for the night check, or nil when it is not known.
    func partnerTimeZone() async -> TimeZone?
    /// Reads the partner and their time zone again in the background, so a call can start and
    /// ring without waiting for them.
    func refreshCallContext()
    /// A view that shows one side's video. The engine keeps it current while the call runs.
    func makeVideoView(_ source: CallVideoSource) -> UIView
    /// A clear view to put behind the partner's photo, which Picture in Picture grows out of while
    /// the partner shows no video.
    func makePictureInPictureAnchor(partnerPhoto: UUID?, partnerName: String) -> UIView
}

/// The live call for the whole app. The call screen, the bubble and the call buttons read it from
/// the environment. Only the engine changes `session` and `backCameraZoom`.
@MainActor
@Observable
final class CallCenter {
    var session: CallSession? {
        didSet {
            let usesProximitySensor = session?.usesProximitySensor ?? false
            if UIDevice.current.isProximityMonitoringEnabled != usesProximitySensor {
                UIDevice.current.isProximityMonitoringEnabled = usesProximitySensor
            }
            sessionDidChange?(oldValue, session)
        }
    }
    /// Hears each change to `session` as it happens, before any view draws it, so the call's
    /// overlay can decide in the same change whether the call shows full or small
    /// (`CallOverlayModel`).
    @ObservationIgnored var sessionDidChange: ((_ old: CallSession?, _ new: CallSession?) -> Void)?
    /// Nil unless the back camera is on and sending. Kept out of `session`, because the call
    /// screen animates every change to it, and the zoom slider would then lag behind the finger.
    var backCameraZoom: CallCameraZoom?
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
