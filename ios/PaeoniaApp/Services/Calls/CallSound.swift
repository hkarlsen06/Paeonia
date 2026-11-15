import AVFoundation
import OSLog
@preconcurrency import LiveKitWebRTC

/// The call's own sounds, `CallSound<rawValue>.caf` in Resources/CallSounds.
/// `ios/Scripts/game-sounds.swift` makes them.
nonisolated enum CallSound: String, CaseIterable, Sendable {
    /// Loops on the caller's phone while the partner's phone rings.
    case ringback = "Ringback"
    /// Plays once on both phones when the call first connects.
    case connected = "Connected"
}

/// Plays the call's sounds. Once WebRTC's audio engine runs, they play inside it: the player is
/// connected to the engine's main mixer next to the partner's voice (`LKRTCAudioDeviceModuleDelegate`).
/// Before that, as for the ringback, they play with `AVAudioPlayer` in the call's audio session.
/// Nothing plays in a call before the system activates its audio.
///
/// The engine calls the delegate methods on its own thread, and the lock keeps them in order with
/// `play` and `setRingback` from the main thread.
nonisolated final class CallSoundPlayer: NSObject, LKRTCAudioDeviceModuleDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let engineNode = AVAudioPlayerNode()
    private let buffers: [CallSound: AVAudioPCMBuffer]
    private let players: [CallSound: AVAudioPlayer]
    // Only touched under `lock`.
    private weak var engine: AVAudioEngine?

    override init() {
        var buffers: [CallSound: AVAudioPCMBuffer] = [:]
        var players: [CallSound: AVAudioPlayer] = [:]
        for sound in CallSound.allCases {
            guard let url = Bundle.main.url(forResource: "CallSound\(sound.rawValue)", withExtension: "caf") else {
                continue
            }
            buffers[sound] = Self.buffer(from: url)
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.numberOfLoops = sound == .ringback ? -1 : 0
                players[sound] = player
            }
        }
        self.buffers = buffers
        self.players = players
    }

    private static func buffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

    func play(_ sound: CallSound) {
        lock.withLock { start(sound) }
    }

    func setRingback(_ isOn: Bool) {
        lock.withLock {
            if isOn {
                start(.ringback)
            } else {
                stop(.ringback)
            }
        }
    }

    func stopAll() {
        lock.withLock {
            for sound in CallSound.allCases {
                stop(sound)
            }
        }
    }

    private func start(_ sound: CallSound) {
        if startInEngine(sound) {
            CallAudio.log.notice("\(sound.rawValue, privacy: .public) playing in the engine")
        } else if let player = players[sound] {
            player.currentTime = 0
            let isPlaying = player.play()
            CallAudio.log.notice("\(sound.rawValue, privacy: .public) playing outside the engine: \(isPlaying)")
        }
    }

    private func startInEngine(_ sound: CallSound) -> Bool {
        guard let engine, engine.isRunning, engineNode.engine === engine, let buffer = buffers[sound] else {
            return false
        }
        engineNode.stop()
        engineNode.scheduleBuffer(buffer, at: nil, options: sound == .ringback ? .loops : [])
        do {
            try engineNode.playAudio()
            return true
        } catch {
            CallAudio.log.error("engine player did not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func stop(_ sound: CallSound) {
        engineNode.stop()
        players[sound]?.stop()
    }

    // MARK: The engine

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, didCreateEngine engine: AVAudioEngine) -> Int {
        lock.withLock {
            engine.attach(engineNode)
            self.engine = engine
        }
        CallAudio.log.notice("engine created")
        return 0
    }

    // swiftlint:disable:next function_parameter_count
    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        engine: AVAudioEngine,
        configureOutputFromSource source: AVAudioNode,
        toDestination destination: AVAudioNode?,
        format: AVAudioFormat,
        context: [AnyHashable: Any]
    ) -> Int {
        lock.withLock {
            if let format = buffers[.ringback]?.format, engineNode.engine === engine {
                do {
                    try engine.connectNode(engineNode, to: engine.mainMixerNode, format: format)
                } catch {
                    CallAudio.log.error("engine player not connected: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        CallAudio.log.notice("engine output connected: \(format, privacy: .public)")
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        willStartEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool,
        isRecordingEnabled: Bool
    ) -> Int {
        CallAudio.log.notice("engine starting: playout=\(isPlayoutEnabled) recording=\(isRecordingEnabled)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            CallAudio.logState("engine started")
        }
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        willEnableEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool,
        isRecordingEnabled: Bool,
        isVoiceProcessingEnabled: Bool
    ) -> Int {
        CallAudio.log.notice("""
            engine enabling: playout=\(isPlayoutEnabled) recording=\(isRecordingEnabled) \
            voiceProcessing=\(isVoiceProcessingEnabled)
            """)
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        didStopEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool,
        isRecordingEnabled: Bool
    ) -> Int {
        CallAudio.log.notice("engine stopped")
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        didDisableEngine engine: AVAudioEngine,
        isPlayoutEnabled: Bool,
        isRecordingEnabled: Bool
    ) -> Int {
        0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        willReleaseEngine engine: AVAudioEngine
    ) -> Int {
        lock.withLock {
            engineNode.stop()
            if engineNode.engine === engine {
                engine.detach(engineNode)
            }
            self.engine = nil
        }
        CallAudio.log.notice("engine released")
        return 0
    }

    // swiftlint:disable:next function_parameter_count
    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        engine: AVAudioEngine,
        configureInputFromSource source: AVAudioNode?,
        toDestination destination: AVAudioNode,
        format: AVAudioFormat,
        context: [AnyHashable: Any]
    ) -> Int {
        0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        didReceiveSpeechActivityEvent speechActivityEvent: LKRTCSpeechActivityEvent
    ) {}

    func audioDeviceModuleDidUpdateDevices(_ audioDeviceModule: LKRTCAudioDeviceModule) {}
}
