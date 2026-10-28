import AVFoundation

@MainActor
final class PairingCelebrationSoundPlayer {
    private var players: [String: AVAudioPlayer] = [:]

    func prepare() {
        guard players.isEmpty else { return }
        for name in ["Gather", "Release"] {
            guard let url = Bundle.main.url(forResource: "Pairing\(name)", withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.enableRate = true
            player.prepareToPlay()
            players[name] = player
        }
    }

    func absorb(duration: Double) {
        play("Gather", rate: 1.45 / max(duration, 0.01))
    }

    func release(duration: Double) {
        players["Gather"]?.setVolume(0, fadeDuration: 0.035)
        play("Release", rate: 0.9 / max(duration, 0.01))
    }

    func stop() {
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }

    private func play(_ name: String, rate: Double) {
        guard let player = players[name] else { return }
        PaeoniaAudioSession.useAmbient()
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        player.volume = 0.65
        player.rate = Float(min(max(rate, 0.5), 2))
        player.play()
    }
}
