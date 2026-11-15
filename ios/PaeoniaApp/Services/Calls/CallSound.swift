import AVFoundation
import OSLog

/// The call's own sounds, `CallSound<rawValue>.caf` in Resources/CallSounds.
/// `ios/Scripts/game-sounds.swift` makes them.
nonisolated enum CallSound: String, CaseIterable, Sendable {
    /// Loops on the caller's phone while the partner's phone rings.
    case ringback = "Ringback"
    /// Plays once on both phones when the call first connects.
    case connected = "Connected"
}

/// Plays the call's sounds. On a phone the call engine plays them only once the system has
/// activated the call's audio session, so they follow the call's route: the speaker, the
/// earpiece or AirPods. `CallMachine` keeps WebRTC's voice processing off while they play,
/// because it turns other sound down, and nothing here touches the session. They play at full
/// gain, the call level in `docs/game-audio.md`.
///
/// The players run on one serial queue, because `AVAudioPlayer` talks to the audio session,
/// which can block the main thread. The queue keeps every start and stop in order.
nonisolated final class CallSoundPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "no.paeonia.app.callSounds", qos: .userInitiated)
    // Only touched on `queue`.
    private var players: [CallSound: AVAudioPlayer] = [:]

    func play(_ sound: CallSound) {
        queue.async { self.start(sound) }
    }

    func setRingback(_ isOn: Bool) {
        queue.async {
            if isOn {
                self.start(.ringback)
            } else {
                self.players[.ringback]?.stop()
            }
        }
    }

    func stopAll() {
        queue.async {
            for player in self.players.values {
                player.stop()
            }
        }
    }

    private func start(_ sound: CallSound) {
        guard let player = player(for: sound) else { return }
        player.currentTime = 0
        let isPlaying = player.play()
        CallAudio.log.notice("\(sound.rawValue, privacy: .public) play=\(isPlaying) gain=\(player.volume)")
    }

    private func player(for sound: CallSound) -> AVAudioPlayer? {
        if let player = players[sound] {
            return player
        }
        guard let url = Bundle.main.url(forResource: "CallSound\(sound.rawValue)", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.numberOfLoops = sound == .ringback ? -1 : 0
        players[sound] = player
        return player
    }
}
