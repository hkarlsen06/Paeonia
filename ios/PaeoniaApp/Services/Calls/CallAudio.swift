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
    /// The engine's availability, the call's sounds (`CallSoundPlayer`) and the state log change
    /// here, one after another. Each change waits for WebRTC's audio thread or the system's
    /// audio service, up to 160 ms on an iPhone, and on the main thread it stalled the call
    /// screen for about 320 ms as it slid up when a call started.
    nonisolated static let queue = DispatchQueue(label: "no.paeonia.app.call-audio", qos: .userInitiated)

    nonisolated private static var module: LKRTCAudioDeviceModule {
        CallMediaFactory.shared.audioDeviceModule
    }

    /// The engine may not start before the system activates a call's audio. While voice
    /// processing runs, it turns the call's own sounds down as little as iOS allows. A muted
    /// microphone is muted at the engine's input mixer: voice processing's own mute crashed the
    /// system's audio service on an iPhone (`ATSecureVADManager::setMuteState` in audiomxd).
    nonisolated static func configureAtLaunch(sounds: CallSoundPlayer) {
        queue.async {
            module.observer = sounds
            module.duckingLevel = .min
            module.setMuteMode(.inputMixer)
            setEngineAvailable(false)
        }
    }

    nonisolated private static let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]

    /// The person's Speaker choice for the call, kept so the session can be set up again with it
    /// after the system's audio service restarts.
    private static var usesSpeaker = true

    /// Sets the call's category before the system reports the call.
    static func prepareCategory() {
        usesSpeaker = true
        applyCallCategory(usesSpeaker: true)
    }

    /// iOS mutes haptics while the microphone records unless the session allows them, and
    /// `CallHaptics` plays during the call.
    nonisolated private static func applyCallCategory(usesSpeaker: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .default,
            options: usesSpeaker ? options.union(.defaultToSpeaker) : options
        )
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
    }

    /// The system's audio service restarted. That puts the session back at its defaults and
    /// leaves the engine and every player from before dead, in a call or not. This releases the
    /// engine, gives the session its category again, replaces the players, and makes the engine
    /// available again if the system had activated the call's audio. WebRTC's audio module
    /// creates a new `AVAudioEngine` each time it becomes available, and has no handling of its
    /// own for a restart. Nothing here activates the session, which stays the system's job.
    ///
    /// `onEngineBack` runs on the main thread once the module has its engine again. It never
    /// runs when the system had not activated the call's audio, or when the engine stays
    /// refused, such as while the session is no longer active.
    static func rebuildAfterServiceRestart(
        sounds: CallSoundPlayer,
        isInCall: Bool,
        onEngineBack: @escaping @MainActor @Sendable () -> Void
    ) {
        let usesSpeaker = usesSpeaker
        queue.async {
            let wasAvailable = isEngineAvailable
            if wasAvailable {
                setEngineAvailable(false)
                self.onEngineBack = onEngineBack
            }
            if isInCall {
                applyCallCategory(usesSpeaker: usesSpeaker)
            } else {
                PaeoniaAudioSession.useAmbient()
            }
            sounds.rebuild()
            if wasAvailable {
                setEngineAvailable(true)
            }
        }
    }

    /// Prepares the microphone without starting the engine, so the engine starts once, with the
    /// partner's voice and the microphone together, when the phones connect. Started for the
    /// voice alone, it restarted for the microphone a moment later and cut off the connected
    /// chime.
    nonisolated static func didActivate(_: AVAudioSession) {
        queue.async {
            noteSystemActivation(true)
            setEngineAvailable(true)
            module.setRecordingAlwaysPreparedMode(true)
        }
    }

    /// Tells WebRTC's own audio session object that the system activated or deactivated the
    /// call's audio. After an interruption ends, or the audio service restarts, that object sets
    /// the session active or inactive by its own count of activations. Left at zero, the count
    /// made it deactivate the call's session in the middle of a call. Runs on `queue`.
    nonisolated private static func noteSystemActivation(_ isActive: Bool) {
        guard isActive != hasSystemActivation else { return }
        hasSystemActivation = isActive
        let session = AVAudioSession.sharedInstance()
        if isActive {
            LKRTCAudioSession.sharedInstance().audioSessionDidActivate(session)
        } else {
            LKRTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
        }
    }

    /// Only touched on `queue`.
    nonisolated(unsafe) private static var hasSystemActivation = false

    nonisolated static func didDeactivate(_: AVAudioSession) {
        stopEngine()
    }

    /// Stops the engine when the call ends, even if the system never deactivates its audio.
    nonisolated static func stopEngine() {
        queue.async {
            module.setRecordingAlwaysPreparedMode(false)
            setEngineAvailable(false)
            noteSystemActivation(false)
        }
    }

    /// Runs on `queue`. The module refuses to build its engine while the session is still
    /// changing, such as right after a new category, when the microphone reports no format yet.
    /// It leaves the engine unavailable then, and the call would stay silent, so this tries
    /// again for as long as the engine is still wanted.
    nonisolated private static func setEngineAvailable(_ isOn: Bool, attempt: Int = 1) {
        isEngineAvailable = isOn
        let availability = ObjCBool(isOn)
        let result = module.setEngineAvailability(
            LKRTCAudioEngineAvailability(isInputAvailable: availability, isOutputAvailable: availability)
        )
        guard isOn, result != 0 else {
            let engineBack = onEngineBack
            onEngineBack = nil
            if isOn, let engineBack {
                Task { @MainActor in engineBack() }
            }
            return
        }
        log.error("engine not available, error \(result), attempt \(attempt)")
        guard attempt < engineAttempts else { return }
        queue.asyncAfter(deadline: .now() + engineRetryDelay) {
            guard isEngineAvailable else { return }
            setEngineAvailable(true, attempt: attempt + 1)
        }
    }

    /// Enough tries to last until the call gives up on its audio (`CallMachine.audioActivationTimeout`).
    nonisolated private static let engineAttempts = 15
    nonisolated private static let engineRetryDelay: TimeInterval = 0.3
    /// Set by `rebuildAfterServiceRestart`. Only touched on `queue`.
    nonisolated(unsafe) private static var onEngineBack: (@MainActor @Sendable () -> Void)?

    /// Only touched on `queue`.
    nonisolated(unsafe) private static var isEngineAvailable = false

    nonisolated static let log = Logger(subsystem: "no.paeonia.app", category: "CallAudio")

    /// Logs the session's state at each audio step of a call. A device's console shows it when
    /// the app launches with `OS_ACTIVITY_DT_MODE=YES`.
    nonisolated static func logState(_ moment: String) {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            let outputs = session.currentRoute.outputs
                .map { "\($0.portType.rawValue)/\($0.channels?.count ?? 0)ch" }
                .joined(separator: ",")
            log.notice("""
                \(moment, privacy: .public): outputs=\(outputs, privacy: .public) \
                category=\(session.category.rawValue, privacy: .public) \
                mode=\(session.mode.rawValue, privacy: .public) \
                options=\(session.categoryOptions.rawValue) volume=\(session.outputVolume) \
                engineRunning=\(module.isEngineRunning) playing=\(module.isPlaying) recording=\(module.isRecording) \
                otherAudio=\(session.isOtherAudioPlaying)
                """)
        }
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
        usesSpeaker = isOn
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
    nonisolated static func restartForMicrophone() {
        queue.async {
            guard isEngineAvailable else { return }
            setEngineAvailable(false)
            setEngineAvailable(true)
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
