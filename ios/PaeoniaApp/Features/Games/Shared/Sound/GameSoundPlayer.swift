import AVFoundation

/// Plays `GameSound`s with low latency and several at once. The app's audio session is
/// `.ambient` (`PaeoniaAudioSession`), so the sounds mix with the person's music instead
/// of pausing it, and the silent switch mutes them.
///
/// All work runs on one serial queue, so a tap never waits for a file or for the engine.
nonisolated final class GameSoundPlayer: @unchecked Sendable {
    static let shared = GameSoundPlayer()

    /// How many sounds can overlap. A new sound past this cuts off the oldest.
    private static let voiceCount = 8
    /// The engine pauses after this long without a sound, so it uses no power between turns.
    private static let idleSeconds = 8.0

    private let queue = DispatchQueue(label: "no.paeonia.app.gameSounds", qos: .userInteractive)

    // Only touched on `queue`.
    private let engine = AVAudioEngine()
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var variants: [GameSound: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [GameSound: Int] = [:]
    private var idlePause: DispatchWorkItem?

    private init() {}

    func play(_ sound: GameSound, volume: Float) {
        queue.async { self.playNow(sound, volume: volume) }
    }

    /// Loads every sound and starts the engine, so the first sound of a game is on time.
    func prepare() {
        queue.async {
            for sound in GameSound.allCases { _ = self.buffers(for: sound) }
            if let format = self.variants.values.first?.first?.format, self.start(format: format) {
                self.scheduleIdlePause()
            }
        }
    }

    private func playNow(_ sound: GameSound, volume: Float) {
        let buffers = buffers(for: sound)
        guard !buffers.isEmpty, start(format: buffers[0].format) else { return }
        // A random variant that is not the one just played, so repeats never sound the same.
        var index = Int.random(in: buffers.indices)
        if buffers.count > 1, index == lastVariant[sound] {
            index = (index + 1) % buffers.count
        }
        lastVariant[sound] = index

        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = min(max(volume, 0), 1) * Float.random(in: 0.88...1)
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

    /// Starts the engine if it is not running. A call, Siri or a route change stops it,
    /// and the next sound starts it again. The files share one format, which the voices
    /// are connected with once.
    private func start(format: AVAudioFormat) -> Bool {
        guard !engine.isRunning else { return true }
        do {
            if voices.isEmpty {
                for _ in 0..<Self.voiceCount {
                    let voice = AVAudioPlayerNode()
                    engine.attach(voice)
                    try engine.connectNode(voice, to: engine.mainMixerNode, format: format)
                    voices.append(voice)
                }
            }
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func scheduleIdlePause() {
        idlePause?.cancel()
        let pause = DispatchWorkItem { [weak self] in self?.engine.pause() }
        idlePause = pause
        queue.asyncAfter(deadline: .now() + Self.idleSeconds, execute: pause)
    }
}
