import Foundation
import Testing
@testable import PaeoniaApp

/// When each word of a line that writes itself in appears.
struct StoryChainPageArrivalTimingTests {
    private let partner = StoryChainArrivalTiming.partner
    private let mine = StoryChainArrivalTiming.mine

    @Test func theDesignedNumbersAreTheDefaults() {
        #expect(partner.wordDuration == 0.35)
        #expect(partner.wordGap == 0.045)
        #expect(partner.maxTotal == 1.6)
        #expect(partner.rise == 4)
        #expect(partner.blur == 6)
        #expect(mine.wordGap == 0.030)
    }

    @Test func aShortLineStartsHiddenAndEndsSharp() {
        let count = 8
        let total = partner.totalDuration(wordCount: count)

        // The last word starts 7 gaps in and then takes 0.35 s.
        #expect(abs(total - (0.35 + 0.045 * 7)) < 1e-6)
        for index in 0..<count {
            #expect(partner.progress(wordIndex: index, wordCount: count, elapsed: 0) == 0)
            #expect(partner.progress(wordIndex: index, wordCount: count, elapsed: total) == 1)
        }
    }

    @Test func wordsStartOneGapApart() {
        // The second word has not started when the first one has run for 45 ms.
        #expect(partner.progress(wordIndex: 0, wordCount: 8, elapsed: 0.045) > 0)
        #expect(partner.progress(wordIndex: 1, wordCount: 8, elapsed: 0.045) == 0)
        #expect(partner.progress(wordIndex: 1, wordCount: 8, elapsed: 0.09) > 0)
        #expect(abs(partner.gap(wordCount: 8) - 0.045) < 1e-6)
    }

    @Test func aLongLineIsCompressedToTheMostItMayTake() {
        // 28 words still fit with the full gap: 0.35 + 27 * 0.045 = 1.565 s.
        #expect(abs(partner.gap(wordCount: 28) - 0.045) < 1e-6)
        #expect(partner.totalDuration(wordCount: 28) <= 1.6)

        for count in [29, 40, 120] {
            let total = partner.totalDuration(wordCount: count)
            #expect(abs(total - 1.6) < 1e-6)
            #expect(partner.gap(wordCount: count) < 0.045)
            // The last word is sharp exactly when the line is done.
            #expect(partner.progress(wordIndex: count - 1, wordCount: count, elapsed: total) == 1)
        }
    }

    @Test func progressNeverGoesBackwardsInTime() {
        for count in [1, 5, 40] {
            for index in 0..<count {
                var previous = 0.0
                for step in 0...200 {
                    let elapsed = Double(step) * 0.01
                    let value = partner.progress(wordIndex: index, wordCount: count, elapsed: elapsed)
                    #expect(value >= previous)
                    #expect(value >= 0 && value <= 1)
                    previous = value
                }
            }
        }
    }

    @Test func laterWordsAreNeverAheadOfEarlierOnes() {
        let count = 12
        for step in 0...80 {
            let elapsed = Double(step) * 0.01
            let values = (0..<count).map { partner.progress(wordIndex: $0, wordCount: count, elapsed: elapsed) }
            #expect(values == values.sorted(by: >))
        }
    }

    @Test func aLineIAmSendingWritesInFasterThanAPartnersLine() {
        #expect(mine.totalDuration(wordCount: 10) < partner.totalDuration(wordCount: 10))
        #expect(abs(mine.gap(wordCount: 10) - 0.030) < 1e-6)
    }

    @Test func oneWordHasNoGapAndAnEmptyLineHasNoTime() {
        #expect(partner.gap(wordCount: 1) == 0)
        #expect(abs(partner.totalDuration(wordCount: 1) - 0.35) < 1e-6)
        #expect(partner.totalDuration(wordCount: 0) == 0)
        #expect(partner.progress(wordIndex: 0, wordCount: 0, elapsed: 0) == 1)
    }

    @Test func aWordIndexOutsideTheLineIsClamped() {
        #expect(partner.progress(wordIndex: -3, wordCount: 4, elapsed: 0) == 0)
        #expect(partner.progress(wordIndex: 9, wordCount: 4, elapsed: 10) == 1)
    }

    @Test func reduceMotionFadesTheWholeLineAtOnce() {
        var timing = partner
        timing.fadeDuration = 0.24

        #expect(timing.totalDuration(wordCount: 12, reduceMotion: true) == 0.24)
        #expect(timing.fadeProgress(elapsed: 0) == 0)
        #expect(abs(timing.fadeProgress(elapsed: 0.12) - 0.5) < 1e-6)
        #expect(timing.fadeProgress(elapsed: 5) == 1)
        #expect(timing.fadeProgress(elapsed: -1) == 0)
    }
}
