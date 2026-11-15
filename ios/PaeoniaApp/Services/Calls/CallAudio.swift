import AVFoundation
import OSLog
@preconcurrency import WebRTC

/// The call's side of the audio session. The system activates the session for a call, and
/// WebRTC's audio runs only inside that activation, when `CallMachine` asks for it
/// (`isMediaAudioOn`). Nothing here calls `setActive`.
///
/// The session is in the default mode until WebRTC's audio starts, and in `voiceChat` after.
/// In `voiceChat` iOS plays sound that skips voice processing far quieter, so the ringback was
/// barely audible on an iPhone even at full gain.
enum CallAudio {
    private static var rtcSession: RTCAudioSession {
        RTCAudioSession.sharedInstance()
    }

    /// Every category change keeps these options. WebRTC sets its category again when its
    /// audio starts, and a real change there would drop the speaker for the earpiece.
    private static let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]

    /// Turns on WebRTC's manual audio, before any peer connection exists.
    static func configureAtLaunch() {
        rtcSession.useManualAudio = true
        rtcSession.isAudioEnabled = false
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = options
        RTCAudioSessionConfiguration.setWebRTC(configuration)
    }

    /// Sets the call's category before the system activates the session for it.
    static func prepareCategory() {
        let session = rtcSession
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
    }

    /// Switches the mode and keeps the speaker if it had the sound, because a mode change can
    /// move the sound back to the earpiece.
    private static func setMode(_ mode: AVAudioSession.Mode) {
        let session = rtcSession
        guard session.mode != mode.rawValue else { return }
        let wasSpeaker = currentRoute() == .speaker
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        do {
            try session.setCategory(.playAndRecord, mode: mode, options: options)
        } catch {
            log.error("setCategory failed: \(error.localizedDescription, privacy: .public)")
        }
        if wasSpeaker {
            try? session.overrideOutputAudioPort(.speaker)
        }
        logState("mode \(mode.rawValue)")
    }

    /// The call's sounds play in the default mode until WebRTC's audio starts.
    static func didActivate(_ audioSession: AVAudioSession) {
        rtcSession.audioSessionDidActivate(audioSession)
        if !rtcSession.isAudioEnabled {
            setMode(.default)
        }
    }

    /// Starts or stops WebRTC's voice processing unit, which plays the partner and records the
    /// microphone, in `voiceChat`. While it runs, iOS turns other sound down, the call's own
    /// sounds included.
    static func setMediaAudio(_ isOn: Bool) {
        if isOn {
            setMode(.voiceChat)
        }
        if rtcSession.isAudioEnabled != isOn {
            rtcSession.isAudioEnabled = isOn
        }
    }

    static func didDeactivate(_ audioSession: AVAudioSession) {
        rtcSession.audioSessionDidDeactivate(audioSession)
        rtcSession.isAudioEnabled = false
    }

    nonisolated static let log = Logger(subsystem: "no.paeonia.app", category: "CallAudio")

    /// Logs the session's state at each audio step of a call. A device's console shows it when
    /// the app launches with `OS_ACTIVITY_DT_MODE=YES`.
    static func logState(_ moment: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue)/\($0.channels?.count ?? 0)ch" }
            .joined(separator: ",")
        log.notice("""
            \(moment, privacy: .public): outputs=\(outputs, privacy: .public) \
            category=\(session.category.rawValue, privacy: .public) mode=\(session.mode.rawValue, privacy: .public) \
            options=\(session.categoryOptions.rawValue) volume=\(session.outputVolume) \
            webrtcAudio=\(rtcSession.isAudioEnabled) webrtcActive=\(rtcSession.isActive) \
            otherAudio=\(session.isOtherAudioPlaying)
            """)
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

    /// Sends the sound to the speaker, or back to the route the system picks, which is the
    /// earpiece unless something such as AirPods or a car is connected.
    static func useSpeaker(_ isOn: Bool) {
        let session = rtcSession
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.overrideOutputAudioPort(isOn ? .speaker : .none)
    }

    /// Asks for the microphone when the person has not answered yet.
    static func microphoneAllowed() async -> Bool {
        switch microphonePermission {
        case .granted:
            true
        case .denied:
            false
        default:
            await AVAudioApplication.requestRecordPermission()
        }
    }

    static var microphonePermission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    /// Starts WebRTC's audio again once the microphone is allowed during a call, so it records.
    /// Before WebRTC's audio starts there is nothing to restart.
    static func restartForMicrophone() {
        guard rtcSession.isAudioEnabled else { return }
        rtcSession.isAudioEnabled = false
        rtcSession.isAudioEnabled = true
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
