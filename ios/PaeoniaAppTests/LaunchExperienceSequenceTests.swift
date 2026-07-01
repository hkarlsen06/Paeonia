import Testing
@testable import PaeoniaApp

/// Covers the cold-launch intro's gating rule: the app is only unmasked once *both*
/// the scripted branded hold has played *and* the first real surface is ready, no
/// matter which of the two finishes first. Getting this wrong either flashes a
/// half-loaded screen or holds on a blank one.
struct LaunchExperienceSequenceTests {
    @Test func startsOnTheMarkMatchingTheSystemSplash() {
        let sequence = LaunchExperienceSequence()

        #expect(sequence.phase == .mark)
        #expect(sequence.isContentReady == false)
        #expect(sequence.hasHeldWordmark == false)
    }

    @Test func revealMovesFromMarkToWordmark() {
        var sequence = LaunchExperienceSequence()

        sequence.revealWordmark()

        #expect(sequence.phase == .wordmark)
    }

    @Test func revealOnlyAppliesFromTheMarkPhase() {
        var sequence = LaunchExperienceSequence()
        sequence.revealWordmark()
        sequence.markContentReady()
        sequence.markWordmarkHoldElapsed()
        #expect(sequence.phase == .unmasking)

        // A late, stray reveal must not knock an in-progress unmask back to wordmark.
        sequence.revealWordmark()

        #expect(sequence.phase == .unmasking)
    }

    @Test func holdElapsingBeforeContentReadyKeepsHoldingOnTheWordmark() {
        var sequence = LaunchExperienceSequence()
        sequence.revealWordmark()

        sequence.markWordmarkHoldElapsed()

        // Content is still loading, so we keep showing the branded wordmark.
        #expect(sequence.phase == .wordmark)

        sequence.markContentReady()

        #expect(sequence.phase == .unmasking)
    }

    @Test func contentReadyBeforeHoldElapsedStillWaitsForTheHold() {
        var sequence = LaunchExperienceSequence()
        sequence.revealWordmark()

        sequence.markContentReady()

        // The reveal must not jump in early just because content loaded fast.
        #expect(sequence.phase == .wordmark)

        sequence.markWordmarkHoldElapsed()

        #expect(sequence.phase == .unmasking)
    }

    @Test func contentReadyDuringTheMarkPhaseDoesNotSkipTheReveal() {
        var sequence = LaunchExperienceSequence()

        // A very fast launch can be ready before the wordmark is even revealed; the
        // reveal beat must still play rather than jumping straight to the unmask.
        sequence.markContentReady()
        #expect(sequence.phase == .mark)

        sequence.revealWordmark()
        #expect(sequence.phase == .wordmark)

        // The unmask only begins once the scripted hold reports in, after the reveal.
        sequence.markWordmarkHoldElapsed()
        #expect(sequence.phase == .unmasking)
    }

    @Test func finishOnlyCompletesAnInProgressUnmask() {
        var sequence = LaunchExperienceSequence()

        // Finishing before the unmask has begun is a no-op.
        sequence.finishUnmask()
        #expect(sequence.phase == .mark)

        sequence.revealWordmark()
        sequence.markWordmarkHoldElapsed()
        sequence.markContentReady()
        #expect(sequence.phase == .unmasking)

        sequence.finishUnmask()
        #expect(sequence.phase == .finished)
    }

    @Test func repeatedSignalsAreIdempotent() {
        var sequence = LaunchExperienceSequence()
        sequence.revealWordmark()
        sequence.markContentReady()
        sequence.markContentReady()
        sequence.markWordmarkHoldElapsed()
        sequence.markWordmarkHoldElapsed()

        #expect(sequence.phase == .unmasking)

        sequence.finishUnmask()
        sequence.finishUnmask()

        #expect(sequence.phase == .finished)
    }
}
