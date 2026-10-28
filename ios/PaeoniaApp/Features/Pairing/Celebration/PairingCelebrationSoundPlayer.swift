import AVFoundation

@MainActor
final class PairingCelebrationSoundPlayer {
    private var players: [String: AVAudioPlayer] = [:]

    func prepare() {
        guard players.isEmpty else { return }
        for name in ["Gather", "Release"] {
            guard let url = Bundle.main.url(forResource: "Pairing\(name)", withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[name] = player
        }
    }

    func absorb() {
        play("Gather")
    }

    func release() {
        players["Gather"]?.setVolume(0, fadeDuration: 0.035)
        play("Release")
    }

    func stop() {
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }

    private func play(_ name: String) {
        guard let player = players[name] else { return }
        PaeoniaAudioSession.useAmbient()
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        player.volume = 0.65
        player.play()
    }
}
