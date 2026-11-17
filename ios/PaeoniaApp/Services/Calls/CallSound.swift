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
    /// Plays once on both phones when a call they talked on ends. The engine has stopped by then,
    /// so it plays outside it, and the system ends the call once it has played.
    case ended = "Ended"
    /// The partner's phone rings with it. The system call UI loops it as the ringtone, also while
    /// Paeonia is open, and `CallRinger` plays it for developer scenarios, so `CallSoundPlayer`
    /// leaves it out.
    case ring = "Ring"

    var fileName: String {
        "CallSound\(rawValue).caf"
    }

    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: nil)
    }
}

/// Plays the call's sounds. Once WebRTC's audio engine runs, they play inside it: the player is
/// connected to the engine's main mixer next to the partner's voice (`LKRTCAudioDeviceModuleDelegate`).
/// The delegate methods hand the engine to `GameSoundPlayer` too, so game sounds play in it, and
/// to `CallScreenAudio`, which mixes a shared screen's sound into what the microphone sends.
/// Before that, as for the ringback, and after it, as for the ended sound, they play with
/// `AVAudioPlayer` in the call's audio session.
/// Nothing plays in a call before the system activates its audio.
///
/// `play`, `setRingback` and `stopAll` run on `CallAudio.queue`, after the engine changes asked for
/// before them, because starting or stopping a player waits on the system's audio service. The
/// engine calls the delegate methods on its own thread, and the lock keeps the two in order.
nonisolated final class CallSoundPlayer: NSObject, LKRTCAudioDeviceModuleDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let buffers: [CallSound: AVAudioPCMBuffer]
    private let durations: [CallSound: Duration]
    // Only touched under `lock`.
    private var engineNode = AVAudioPlayerNode()
    private var players: [CallSound: AVAudioPlayer]
    private weak var engine: AVAudioEngine?

    override init() {
        var buffers: [CallSound: AVAudioPCMBuffer] = [:]
        for sound in CallSound.allCases where sound != .ring {
            guard let url = sound.url else { continue }
            buffers[sound] = Self.buffer(from: url)
        }
        let players = Self.makePlayers()
        self.buffers = buffers
        self.players = players
        durations = players.mapValues { .seconds($0.duration) }
    }

    private static func makePlayers() -> [CallSound: AVAudioPlayer] {
        var players: [CallSound: AVAudioPlayer] = [:]
        for sound in CallSound.allCases where sound != .ring {
            guard let url = sound.url, let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.numberOfLoops = sound == .ringback ? -1 : 0
            players[sound] = player
        }
        return players
    }

    /// Replaces the players after the system's audio service restarted, which leaves the old
    /// ones dead. Runs on `CallAudio.queue` while the engine is released
    /// (`CallAudio.rebuildAfterServiceRestart`), so the next engine attaches the new node.
    func rebuild() {
        lock.withLock {
            engineNode = AVAudioPlayerNode()
            players = Self.makePlayers()
        }
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

    /// Returns how long the sound lasts.
    @discardableResult
    func play(_ sound: CallSound) -> Duration {
        CallAudio.queue.async { self.lock.withLock { self.start(sound) } }
        return durations[sound] ?? .zero
    }

    func setRingback(_ isOn: Bool) {
        CallAudio.queue.async {
            self.lock.withLock {
                if isOn {
                    self.start(.ringback)
                } else {
                    self.stop(.ringback)
                }
            }
        }
    }

    func stopAll() {
        CallAudio.queue.async {
            self.lock.withLock {
                for sound in CallSound.allCases {
                    self.stop(sound)
                }
            }
        }
    }

    private func start(_ sound: CallSound) {
        if sound != .ended, startInEngine(sound) {
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
        GameSoundPlayer.shared.joinCallEngine(engine)
        CallScreenAudio.shared.joinCallEngine(engine)
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
        GameSoundPlayer.shared.connectInCallEngine(engine)
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
        GameSoundPlayer.shared.leaveCallEngine(engine)
        CallScreenAudio.shared.leaveCallEngine(engine)
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
        CallScreenAudio.shared.connectInput(in: engine, from: source, to: destination, format: format)
        return 0
    }

    func audioDeviceModule(
        _ audioDeviceModule: LKRTCAudioDeviceModule,
        didReceiveSpeechActivityEvent speechActivityEvent: LKRTCSpeechActivityEvent
    ) {}

    func audioDeviceModuleDidUpdateDevices(_ audioDeviceModule: LKRTCAudioDeviceModule) {}
}
