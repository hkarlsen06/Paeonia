import AVFoundation
import CoreMedia
import os
import Synchronization

/// The sound of this phone's shared screen, mixed into what the microphone sends, so the partner
/// hears the video or game being shared. ScreenCaptureKit captures every app's sound but
/// Paeonia's own (`excludesCurrentProcessAudio`), because Paeonia plays the partner's voice.
///
/// WebRTC's audio engine sends what reaches its input mixer. `connectInput` puts the microphone
/// there through `microphone`, a mixer of its own that mute turns down, and the screen's player
/// next to it, so a muted person still shares the screen's sound. WebRTC connects the microphone
/// itself only while nothing else is connected to its input mixer.
///
/// `CallSoundPlayer`, the engine's delegate, hands the engine over. The engine calls it on its
/// own thread and ScreenCaptureKit on its own queue, and the lock keeps the two in order.
nonisolated final class CallScreenAudio: @unchecked Sendable {
    static let shared = CallScreenAudio()

    /// What ScreenCaptureKit is asked for (`CallScreenCapture`): one channel at 48 kHz, Opus's own
    /// rate, which the player plays.
    static let sampleRate = 48_000
    static let channelCount = 1
    private static let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(sampleRate), channels: AVAudioChannelCount(channelCount))
    /// The most sound that waits to play, a quarter of a second. More means the screen's sound
    /// reaches the partner later than its picture, so a buffer that would go past it is dropped.
    private static let mostQueuedFrames = sampleRate / 4

    private let lock = NSLock()
    // Only touched under `lock`.
    private let player = AVAudioPlayerNode()
    private let microphone = AVAudioMixerNode()
    private weak var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    /// The frames scheduled and not yet played. Atomic, because stopping the player can call its
    /// buffers' callbacks while `lock` is held.
    private let queuedFrames = Atomic(0)
    private var isMicrophoneOnOwnMixer = false

    /// Whether mute can silence the microphone alone, because it reaches WebRTC through
    /// `microphone`.
    var mutesMicrophoneAlone: Bool {
        lock.withLock { isMicrophoneOnOwnMixer }
    }

    /// The screen's sound under the voice. Apps master their sound near full loudness, and the
    /// first share with sound drowned the sharer's voice at full volume (2026-11-17).
    private static let volume: Float = 0.3

    func joinCallEngine(_ engine: AVAudioEngine) {
        lock.withLock {
            player.volume = Self.volume
            engine.attach(player)
            engine.attach(microphone)
            self.engine = engine
        }
    }

    /// WebRTC is about to connect its engine's input, which it does again when the route or
    /// format changes. `source` is the microphone, and `mixer` WebRTC's input mixer.
    func connectInput(
        in engine: AVAudioEngine,
        from source: AVAudioNode?,
        to mixer: AVAudioNode,
        format: AVAudioFormat
    ) {
        lock.withLock {
            guard engine === self.engine, let playerFormat = Self.format else { return }
            isMicrophoneOnOwnMixer = false
            do {
                if let source {
                    try engine.connectNode(source, to: microphone, format: format)
                    try engine.connectNode(microphone, to: mixer, format: format)
                    isMicrophoneOnOwnMixer = true
                }
                try engine.connectNode(player, to: mixer, format: playerFormat)
            } catch {
                CallAudio.log.error("screen sound not connected: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func leaveCallEngine(_ engine: AVAudioEngine) {
        lock.withLock {
            guard engine === self.engine else { return }
            player.stop()
            engine.detach(player)
            engine.detach(microphone)
            self.engine = nil
            isMicrophoneOnOwnMixer = false
            queuedFrames.store(0, ordering: .relaxed)
        }
    }

    /// Mute silences the microphone and leaves the shared screen's sound.
    func setMicrophoneMuted(_ isMuted: Bool) {
        lock.withLock {
            microphone.outputVolume = isMuted ? 0 : 1
        }
    }

    /// Plays a piece of the shared screen's sound into what the call sends.
    func play(_ sampleBuffer: CMSampleBuffer) {
        guard let captured = Self.buffer(from: sampleBuffer) else { return }
        lock.withLock {
            let frames = Int(captured.frameLength)
            guard let engine, engine.isRunning, player.engine === engine,
                  max(queuedFrames.load(ordering: .relaxed), 0) + frames <= Self.mostQueuedFrames,
                  let buffer = converted(captured)
            else { return }
            queuedFrames.add(frames, ordering: .relaxed)
            player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                self?.queuedFrames.subtract(frames, ordering: .relaxed)
            }
            guard !player.isPlaying else { return }
            do {
                try player.playAudio()
            } catch {
                CallAudio.log.error("screen sound did not start: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The share ended, so the sound still waiting goes too.
    func stop() {
        lock.withLock {
            player.stop()
            queuedFrames.store(0, ordering: .relaxed)
        }
    }

    /// `captured` in the player's format.
    private func converted(_ captured: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let format = Self.format else { return nil }
        guard captured.format != format else { return captured }
        if converter?.inputFormat != captured.format {
            converter = AVAudioConverter(from: captured.format, to: format)
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(
            (Double(captured.frameLength) * format.sampleRate / captured.format.sampleRate).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var isConsumed = false
        let status = converter.convert(to: output, error: nil) { _, inputStatus in
            if isConsumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            inputStatus.pointee = .haveData
            return captured
        }
        return status == .error ? nil : output
    }

    private static func buffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              let format = AVAudioFormat(formatDescription: description)
        else { return nil }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
