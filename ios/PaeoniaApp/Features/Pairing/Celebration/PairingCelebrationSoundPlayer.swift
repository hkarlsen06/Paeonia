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

    func absorb(releasingAt impact: Double) {
        queue.async {
            guard let gather = self.players["Gather"], let release = self.players["Release"] else { return }
            let deviceTime = release.deviceCurrentTime
            let remaining = impact - CACurrentMediaTime()
            // Give the audio queues 100 ms to start and seek ahead by that interval.
            // Both cues use one device clock, so Gather ends exactly when Release starts.
            let gatherDelay = max(0.1, remaining - gather.duration)
            self.play("Gather", offset: max(0, gather.duration + gatherDelay - remaining),
                      at: deviceTime + gatherDelay)
            let releaseDelay = max(0.1, remaining)
            self.play("Release", offset: releaseDelay - remaining, at: deviceTime + releaseDelay)
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

    private func play(_ name: String, offset: Double = 0, at deviceTime: Double? = nil) {
        guard let player = players[name], offset < player.duration else { return }
        player.currentTime = offset
        player.volume = 1
        if let deviceTime {
            player.play(atTime: deviceTime)
        } else {
            player.play()
        }
    }
}
