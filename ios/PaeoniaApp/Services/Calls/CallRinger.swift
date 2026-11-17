import AudioToolbox
import Foundation

/// Rings for a developer scenario's call, which the system does not know and so does not ring for.
/// A real call rings through the system, even while Paeonia is open. System Sound Services plays
/// `CallSound.ring`, so the ring/silent switch and the person's vibration settings decide whether
/// the phone sounds, vibrates or both, and the call's audio session stays untouched.
enum CallRinger {
    /// One ring starts this often, the length of the sound file, which ends in silence.
    static let period: Duration = .seconds(2.5)

    /// Rings until the task is cancelled.
    static func ring() -> Task<Void, Never> {
        Task {
            guard let url = CallSound.ring.url else { return }
            var soundID: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else { return }
            // Disposing of the sound also cuts off a ring that is still playing.
            defer { AudioServicesDisposeSystemSoundID(soundID) }
            while !Task.isCancelled {
                AudioServicesPlayAlertSound(soundID)
                try? await Task.sleep(for: period)
            }
        }
    }
}
