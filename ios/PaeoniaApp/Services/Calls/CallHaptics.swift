import CoreHaptics
import UIKit

/// The taps an iPhone gives when a phone call is answered and when the other side hangs up. The
/// timings and sharpness are the ones in iOS 27.1's own patterns (`telephony_answer_fpo.ahap` and
/// `end_call.ahap` in TelephonyUtilities.framework), without the system's end tone.
enum CallHaptics {
    /// Four quick taps, the last two crisper, when the partner answers.
    static func connected() {
        // iOS skips it too while the phone is at the person's ear.
        guard !UIDevice.current.proximityState else { return }
        play(taps: [(0, 0.4), (0.095, 0.4), (0.19, 0.65), (0.285, 0.65)])
    }

    /// Three slow taps when the partner hangs up or the call drops.
    static func ended() {
        play(taps: [(0, 0.4), (0.4, 0.4), (0.8, 0.4)])
    }

    private static func play(taps: [(time: TimeInterval, sharpness: Float)]) {
        PaeoniaHapticPattern.play(taps.map { .tap(at: $0.time, sharpness: $0.sharpness) })
    }
}
