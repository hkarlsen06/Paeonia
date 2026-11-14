import AVFoundation
import Synchronization

/// The app's resting audio session. `.ambient` mixes with other apps' audio and follows
/// the silent switch, so nothing Paeonia plays pauses the person's music or podcast.
/// Voice notes switch the session while they record or play, ducking other audio
/// instead of stopping it, and come back here when they finish.
///
/// A call owns the session while it runs. The system activates it for the call, so game
/// sounds, the pairing celebration and voice notes check `isCallActive` and leave it alone.
nonisolated enum PaeoniaAudioSession {
    private static let callActive = Mutex(false)

    /// True from the moment a call starts or rings until it is gone. Readable from any thread.
    static var isCallActive: Bool {
        callActive.withLock { $0 }
    }

    /// Only the call engine sets this.
    static func setCallActive(_ isActive: Bool) {
        callActive.withLock { $0 = isActive }
    }

    static func useAmbient() {
        guard !isCallActive else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }
}
