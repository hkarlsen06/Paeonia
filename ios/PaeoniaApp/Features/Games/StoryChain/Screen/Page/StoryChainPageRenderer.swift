import SwiftUI

/// The blink of the caret after the partner's draft. One blink a second.
nonisolated enum StoryChainCaret {
    static let period: TimeInterval = 1

    /// The caret's opacity at a moment: on for a while, a quick fade, off for a
    /// while, a quick fade back.
    static func opacity(at date: Date) -> Double {
        let time = date.timeIntervalSinceReferenceDate
        let phase = (time / period).truncatingRemainder(dividingBy: 1)
        let wave = 0.5 + 0.9 * cos(phase * 2 * .pi)
        return min(max(wave, 0), 1)
    }
}

/// Draws the story paragraph. It draws every run as SwiftUI would, except the
/// line that is arriving, whose words rise and sharpen one by one, and the
/// caret, which blinks. It also records where each line sits, for taps.
///
/// The renderer is a value that SwiftUI makes again on every change. The view
/// owns `frames` and passes the same box each time.
nonisolated struct StoryChainPageRenderer: TextRenderer {
    typealias AnimatableData = EmptyAnimatableData

    /// The line that writes itself in, and how long it has been going.
    struct Arrival: Equatable, Sendable {
        let lineID: UUID
        var elapsed: TimeInterval
    }

    var arrival: Arrival?
    var timing: StoryChainArrivalTiming
    var reduceMotion: Bool
    var caretOpacity: Double
    let frames: StoryChainLineFrames

    /// Room for the blur of a word that is still arriving.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var recorded: [UUID: [CGRect]] = [:]
        for line in layout {
            for (lineID, rect) in drawRow(line, in: &ctx) {
                recorded[lineID, default: []].append(rect)
            }
        }
        frames.replace(with: recorded)
    }

    /// Draws one row of text and returns where each line sits in it.
    private func drawRow(_ row: Text.Layout.Line, in ctx: inout GraphicsContext) -> [UUID: CGRect] {
        var rects: [UUID: CGRect] = [:]
        for run in row {
            if run[StoryChainCaretTag.self] != nil {
                drawCaret(run, in: &ctx)
                continue
            }
            guard let tag = run[StoryChainLineTag.self] else {
                ctx.draw(run)
                continue
            }
            let reached = progress(of: tag)
            if reached > 0 {
                let rect = run.typographicBounds.rect
                rects[tag.lineID] = rects[tag.lineID].map { $0.union(rect) } ?? rect
            }
            draw(run, progress: reached, in: &ctx)
        }
        return rects
    }

    /// How far a word has come. Words of other lines are done.
    private func progress(of tag: StoryChainLineTag) -> Double {
        guard let arrival, arrival.lineID == tag.lineID else { return 1 }
        if reduceMotion {
            return timing.fadeProgress(elapsed: arrival.elapsed)
        }
        return timing.progress(wordIndex: tag.wordIndex, wordCount: tag.wordCount, elapsed: arrival.elapsed)
    }

    private func draw(_ run: Text.Layout.Run, progress: Double, in ctx: inout GraphicsContext) {
        guard progress < 1 else {
            ctx.draw(run)
            return
        }
        guard progress > 0 else { return }
        var faded = ctx
        faded.opacity = progress
        if !reduceMotion {
            let remaining = 1 - progress
            faded.translateBy(x: 0, y: timing.rise * remaining)
            faded.addFilter(.blur(radius: timing.blur * remaining))
        }
        faded.draw(run)
    }

    private func drawCaret(_ run: Text.Layout.Run, in ctx: inout GraphicsContext) {
        guard caretOpacity > 0 else { return }
        var faded = ctx
        faded.opacity = caretOpacity
        faded.draw(run)
    }
}
