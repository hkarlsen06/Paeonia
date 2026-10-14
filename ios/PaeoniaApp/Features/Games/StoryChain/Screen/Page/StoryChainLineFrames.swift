import CoreGraphics
import Foundation
import os

/// A line the reader tapped, with the rectangle the tap landed in.
nonisolated struct StoryChainLineHit: Equatable, Sendable {
    let lineID: UUID
    let rect: CGRect
}

/// Finds the line under a tap. Pure, so tests run it on plain rectangles.
nonisolated enum StoryChainLineHitTest {
    /// Lines are a few points apart. A tap this close above or below a line still
    /// counts, so the gap between two lines is not a dead zone.
    static let verticalSlop: CGFloat = 3

    private struct Candidate {
        let hit: StoryChainLineHit
        let gap: CGFloat
    }

    /// The line whose rectangle holds the point, or the nearest one within the
    /// vertical slop. Every line can have several rectangles, one for each row of
    /// text it spans. Ties go to the higher row, then the left one.
    static func hit(
        at point: CGPoint,
        in frames: [UUID: [CGRect]],
        verticalSlop: CGFloat = StoryChainLineHitTest.verticalSlop
    ) -> StoryChainLineHit? {
        var best: Candidate?
        for (lineID, rects) in frames {
            for rect in rects where point.x >= rect.minX && point.x <= rect.maxX {
                let gap = max(rect.minY - point.y, point.y - rect.maxY, 0)
                guard gap <= verticalSlop else { continue }
                let candidate = Candidate(hit: StoryChainLineHit(lineID: lineID, rect: rect), gap: gap)
                if let current = best, !precedes(candidate, current) { continue }
                best = candidate
            }
        }
        return best?.hit
    }

    private static func precedes(_ first: Candidate, _ second: Candidate) -> Bool {
        if first.gap != second.gap { return first.gap < second.gap }
        if first.hit.rect.minY != second.hit.rect.minY { return first.hit.rect.minY < second.hit.rect.minY }
        if first.hit.rect.minX != second.hit.rect.minX { return first.hit.rect.minX < second.hit.rect.minX }
        return first.hit.lineID.uuidString < second.hit.lineID.uuidString
    }
}

/// Where each line sits on the page. The renderer fills it while it draws, and
/// the view reads it on a tap. The view owns the box, because the renderer is a
/// value that SwiftUI makes again on every change.
///
/// Rectangles are in the text's own coordinate space, one for each row of text a
/// line spans.
nonisolated final class StoryChainLineFrames: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [UUID: [CGRect]]())

    var frames: [UUID: [CGRect]] {
        lock.withLock { $0 }
    }

    func replace(with frames: [UUID: [CGRect]]) {
        lock.withLock { $0 = frames }
    }

    func hit(at point: CGPoint) -> StoryChainLineHit? {
        StoryChainLineHitTest.hit(at: point, in: frames)
    }
}
