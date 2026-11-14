import AVFoundation
@preconcurrency import WebRTC

/// The call's side of the audio session. The system activates the session for a call, and
/// WebRTC's audio runs only between `conversationManager(_:didActivate:)` and
/// `didDeactivate`. Nothing here calls `setActive`.
enum CallAudio {
    private static var rtcSession: RTCAudioSession {
        RTCAudioSession.sharedInstance()
    }

    /// Turns on WebRTC's manual audio, before any peer connection exists.
    static func configureAtLaunch() {
        rtcSession.useManualAudio = true
        rtcSession.isAudioEnabled = false
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [.allowBluetoothHFP]
        RTCAudioSessionConfiguration.setWebRTC(configuration)
    }

    /// Sets the call's category before the system activates the session for it.
    static func prepareCategory() {
        let session = rtcSession
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    }

    static func didActivate(_ audioSession: AVAudioSession) {
        rtcSession.audioSessionDidActivate(audioSession)
        rtcSession.isAudioEnabled = true
    }

    static func didDeactivate(_ audioSession: AVAudioSession) {
        rtcSession.audioSessionDidDeactivate(audioSession)
        rtcSession.isAudioEnabled = false
    }

    static func currentRoute() -> CallAudioRoute {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return .receiver
        }
        switch output.portType {
        case .builtInReceiver:
            return .receiver
        case .builtInSpeaker:
            return .speaker
        default:
            return .external(name: output.portName)
        }
    }

    /// Sends the sound to the speaker, or back to the route the system picks.
    static func useSpeaker(_ isOn: Bool) {
        let session = rtcSession
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.overrideOutputAudioPort(isOn ? .speaker : .none)
    }

    /// Asks for the microphone when the person has not answered yet.
    static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            true
        case .denied:
            false
        default:
            await AVAudioApplication.requestRecordPermission()
        }
    }

    static func cameraAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }
    }
}
