import Testing
@testable import PaeoniaApp

struct DailyVoiceTakeTests {
    @Test(arguments: [
        (durationMs: 0, isUsable: false),
        (durationMs: 999, isUsable: false),
        (durationMs: 1_000, isUsable: true),
        (durationMs: 60_000, isUsable: true),
    ])
    func takesUnderOneSecondAreNotUsable(durationMs: Int, isUsable: Bool) {
        #expect(DailyVoiceRecorder.isUsableTake(durationMs: durationMs) == isUsable)
    }
}
