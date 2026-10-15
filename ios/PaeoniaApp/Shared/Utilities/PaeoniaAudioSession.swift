import AVFoundation

/// The app's resting audio session. `.ambient` mixes with other apps' audio and follows
/// the silent switch, so nothing Paeonia plays pauses the person's music or podcast.
/// Voice notes switch the session while they record or play, ducking other audio
/// instead of stopping it, and come back here when they finish.
nonisolated enum PaeoniaAudioSession {
    static func useAmbient() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }
}
