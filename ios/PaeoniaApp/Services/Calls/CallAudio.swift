import AVFoundation
import OSLog
@preconcurrency import LiveKitWebRTC

/// The call's side of the audio session and WebRTC's audio engine. The session's category and
/// mode are set once, before the system reports the call, as Apple asks of call apps. During the
/// call the app changes only the speaker option, when the person taps Speaker. The mode is
/// `.default`: in `voiceChat` iOS plays every sound that skips
/// voice processing far quieter, and the ringback was barely audible. The engine turns on voice
/// processing itself, whatever the mode, and iOS then switches the mode to `voiceChat` on its own.
/// The system activates the session, and the engine runs only inside that activation. Nothing
/// here calls `setActive`.
///
/// Every call starts on the speaker through `.defaultToSpeaker`, which leaves AirPods, a headset
/// or a car alone. An output override would not last, because iOS drops it when it switches the
/// mode.
enum CallAudio {
    private static var module: LKRTCAudioDeviceModule {
        CallMediaFactory.shared.audioDeviceModule
    }

    /// The engine may not start before the system activates a call's audio. While voice
    /// processing runs, it turns the call's own sounds down as little as iOS allows. A muted
    /// microphone is muted at the engine's input mixer: voice processing's own mute crashed the
    /// system's audio service on an iPhone (`ATSecureVADManager::setMuteState` in audiomxd).
    static func configureAtLaunch(sounds: CallSoundPlayer) {
        module.observer = sounds
        module.duckingLevel = .min
        module.setMuteMode(.inputMixer)
        setEngineAvailable(false)
    }

    private static let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]

    /// Sets the call's category before the system reports the call. iOS mutes haptics while the
    /// microphone records unless the session allows them, and `CallHaptics` plays during the call.
    static func prepareCategory() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: options.union(.defaultToSpeaker))
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
    }

    /// Prepares the microphone without starting the engine, so the engine starts once, with the
    /// partner's voice and the microphone together, when the phones connect. Started for the
    /// voice alone, it restarted for the microphone a moment later and cut off the connected
    /// chime.
    static func didActivate(_: AVAudioSession) {
        setEngineAvailable(true)
        module.setRecordingAlwaysPreparedMode(true)
    }

    static func didDeactivate(_: AVAudioSession) {
        stopEngine()
    }

    /// Stops the engine when the call ends, even if the system never deactivates its audio.
    static func stopEngine() {
        module.setRecordingAlwaysPreparedMode(false)
        setEngineAvailable(false)
    }

    private static func setEngineAvailable(_ isOn: Bool) {
        isEngineAvailable = isOn
        let availability = ObjCBool(isOn)
        module.setEngineAvailability(
            LKRTCAudioEngineAvailability(isInputAvailable: availability, isOutputAvailable: availability)
        )
    }

    private static var isEngineAvailable = false

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
            engineRunning=\(module.isEngineRunning) playing=\(module.isPlaying) recording=\(module.isRecording) \
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

    /// Sends the sound to the speaker, or to the earpiece unless something such as AirPods or a
    /// car is connected. The override also takes the sound from AirPods to the speaker.
    static func useSpeaker(_ isOn: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: session.mode,
            options: isOn ? options.union(.defaultToSpeaker) : options
        )
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

    /// Starts the engine again once the microphone is allowed during a call, so it records.
    /// Before the system activates the call's audio there is nothing to restart.
    static func restartForMicrophone() {
        guard isEngineAvailable else { return }
        setEngineAvailable(false)
        setEngineAvailable(true)
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
