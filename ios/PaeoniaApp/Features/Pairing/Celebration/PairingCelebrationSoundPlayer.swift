import AVFoundation
import QuartzCore

/// The serial queue keeps audio setup off the animation thread and orders cancellation.
nonisolated final class PairingCelebrationSoundPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "no.paeonia.app.pairingSounds", qos: .userInteractive)

    // Only touched on queue.
    private var players: [String: AVAudioPlayer] = [:]

    func prepare() {
        queue.async {
            PaeoniaAudioSession.useAmbient()
            try? AVAudioSession.sharedInstance().setActive(true)
            for name in ["Gather", "Release"] {
                if self.players[name] == nil,
                   let url = Bundle.main.url(forResource: "Pairing\(name)", withExtension: "caf") {
                    self.players[name] = try? AVAudioPlayer(contentsOf: url)
                }
                self.players[name]?.prepareToPlay()
            }
        }
    }

    func absorb(startedAt start: Double, releasingAt impact: Double) {
        queue.async {
            // Seek past any queue delay so the sustained chord follows the visual pull.
            self.play("Gather", offset: max(0, CACurrentMediaTime() - start))
            guard let release = self.players["Release"] else { return }
            release.currentTime = 0
            release.volume = 0.65
            let deviceTime = release.deviceCurrentTime
            let remaining = impact - CACurrentMediaTime()
            if remaining > 0 {
                release.play(atTime: deviceTime + remaining)
            } else {
                self.play("Release", offset: -remaining)
            }
        }
    }

    func release() {
        queue.async {
            self.players["Gather"]?.setVolume(0, fadeDuration: 0.035)
            self.play("Release")
        }
    }

    func stop() {
        queue.async {
            for player in self.players.values {
                player.stop()
                player.currentTime = 0
            }
        }
    }

    private func play(_ name: String, offset: Double = 0) {
        guard let player = players[name], offset < player.duration else { return }
        player.currentTime = offset
        player.volume = 0.65
        player.play()
    }
}
