import AVFoundation
import OSLog

/// Plays `GameSound`s with low latency and several at once. Outside a call they play on the
/// player's own engine in the app's `.ambient` session (`PaeoniaAudioSession`), so they mix
/// with the person's music instead of pausing it, and the silent switch mutes them.
///
/// During a call they play in the call's own WebRTC engine instead, next to the partner's voice,
/// as the call's sounds do (`CallSoundPlayer`). They follow the speaker, earpiece or AirPods,
/// and the echo canceller hears them, so the partner should not hear them back. The player never
/// touches the call's session and never starts or stops its engine. It stays silent while a
/// call rings and whenever the call's engine is not running.
///
/// All work runs on one serial queue, so a tap never waits for a file or for the engine.
nonisolated final class GameSoundPlayer: @unchecked Sendable {
    static let shared = GameSoundPlayer()

    /// How many sounds can overlap. A new sound past this cuts off the oldest.
    private static let voiceCount = 8
    /// The own engine pauses after this long without a sound, so it uses no power between turns.
    private static let idleSeconds = 8.0
    /// The bundled files are mono 44.1 kHz (docs/game-audio.md), so every voice is connected
    /// with this format, the one the files are read in.
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    private let queue = DispatchQueue(label: "no.paeonia.app.gameSounds", qos: .userInteractive)

    // Only touched on `queue`.
    private let ownEngine = AVAudioEngine()
    /// WebRTC's engine while a call has one. The voices move to it when it arrives. Weak,
    /// because WebRTC drops an engine that fails to start without releasing it and makes a new
    /// one. Kept alive here, the failed engine still owned `CallSoundPlayer`'s node, and
    /// attaching that node to the new engine crashed the app.
    private weak var callEngine: AVAudioEngine?
    private let voices = (0..<voiceCount).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private var variants: [GameSound: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [GameSound: Int] = [:]
    private var idlePause: DispatchWorkItem?

    private init() {}

    func play(_ sound: GameSound, gain: Float, variation: Int? = nil) {
        queue.async { self.playNow(sound, gain: gain, variation: variation) }
    }

    /// Loads every sound and readies the engine, so the first sound of a game is on time.
    /// Each sound loads on its own turn of the queue, so WebRTC waiting to hand over its engine
    /// waits for one file at most.
    func prepare() {
        for sound in GameSound.allCases {
            queue.async { _ = self.buffers(for: sound) }
        }
        queue.async {
            if self.ready() {
                self.scheduleIdlePause()
            }
        }
    }

    private func playNow(_ sound: GameSound, gain: Float, variation: Int?) {
        let buffers = buffers(for: sound)
        guard !buffers.isEmpty, ready() else { return }
        // A random variant that is not the one just played, so repeats never sound the same.
        var index = Int.random(in: buffers.indices)
        if let variation {
            index = variation % buffers.count
        } else if buffers.count > 1, index == lastVariant[sound] {
            index = (index + 1) % buffers.count
        }
        lastVariant[sound] = index

        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = gain
        voice.scheduleBuffer(buffers[index], at: nil, options: .interrupts)
        try? voice.playAudio()
        scheduleIdlePause()
    }

    private func buffers(for sound: GameSound) -> [AVAudioPCMBuffer] {
        if let cached = variants[sound] { return cached }
        var loaded: [AVAudioPCMBuffer] = []
        while let buffer = Self.load("GameSound\(sound.rawValue)\(loaded.count + 1)") {
            loaded.append(buffer)
        }
        variants[sound] = loaded
        return loaded
    }

    private static func load(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

    /// Says whether the voices can play now, on the call's engine during a call or on the own
    /// engine otherwise. The call's engine plays only while WebRTC runs it with the voices
    /// connected. A call without an engine, such as one that still rings, plays nothing.
    /// Otherwise this starts the own engine if it is not running. A call, Siri or a route
    /// change stops it, and the next sound starts it again.
    private func ready() -> Bool {
        if let callEngine {
            return callEngine.isRunning && isConnected(in: callEngine)
        }
        guard !PaeoniaAudioSession.isCallActive else {
            ownEngine.pause()
            return false
        }
        do {
            if !isConnected(in: ownEngine) {
                moveVoices(to: ownEngine)
                try connectVoices(in: ownEngine)
            }
            guard !ownEngine.isRunning else { return true }
            try AVAudioSession.sharedInstance().setActive(true)
            try ownEngine.start()
            return true
        } catch {
            return false
        }
    }

    private func isConnected(in engine: AVAudioEngine) -> Bool {
        voices[0].engine === engine && !engine.outputConnectionPoints(for: voices[0], outputBus: 0).isEmpty
    }

    private func moveVoices(to engine: AVAudioEngine) {
        for voice in voices where voice.engine !== engine {
            voice.stop()
            voice.engine?.detach(voice)
            engine.attach(voice)
        }
    }

    private func connectVoices(in engine: AVAudioEngine) throws {
        guard let format = Self.format else { return }
        for voice in voices {
            try engine.connectNode(voice, to: engine.mainMixerNode, format: format)
        }
    }

    /// Only ever pauses the own engine. The call's engine belongs to WebRTC.
    private func scheduleIdlePause() {
        idlePause?.cancel()
        let pause = DispatchWorkItem { [weak self] in self?.ownEngine.pause() }
        idlePause = pause
        queue.asyncAfter(deadline: .now() + Self.idleSeconds, execute: pause)
    }

    // MARK: The call's engine

    // WebRTC calls these from `CallSoundPlayer`'s engine delegate methods, on its own thread, and
    // the voices must be attached and connected before the method returns, so they wait for the
    // queue. Work on the queue never waits for WebRTC, `CallAudio.queue` or `CallSoundPlayer`.

    /// WebRTC made its engine for a call. The own engine stops and the voices move over.
    func joinCallEngine(_ engine: AVAudioEngine) {
        queue.sync {
            idlePause?.cancel()
            ownEngine.stop()
            moveVoices(to: engine)
            callEngine = engine
        }
    }

    /// WebRTC connected its engine's output, which it does again when the route or format
    /// changes. The voices join the main mixer next to the partner's voice.
    func connectInCallEngine(_ engine: AVAudioEngine) {
        queue.sync {
            guard engine === callEngine, voices[0].engine === engine else { return }
            do {
                try connectVoices(in: engine)
            } catch {
                CallAudio.log.error("game sounds not connected: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// WebRTC is about to release its engine. The voices leave it, and the next sound after
    /// the call moves them back to the own engine.
    func leaveCallEngine(_ engine: AVAudioEngine) {
        queue.sync {
            guard engine === callEngine else { return }
            for voice in voices where voice.engine === engine {
                voice.stop()
                engine.detach(voice)
            }
            callEngine = nil
        }
    }
}
