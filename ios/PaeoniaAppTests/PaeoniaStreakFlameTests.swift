import SwiftUI
import Testing
@testable import PaeoniaApp

/// Guards the streak flame's core visual contract: the liquid surface rises with
/// the fill level (empty at 0, full at 1), and the flame outline stays inside its
/// frame. The count-up timing and haptics are presentational and not covered here.
struct PaeoniaStreakFlameTests {
    private static let rect = CGRect(x: 0, y: 0, width: 100, height: 140)

    @Test func flameShapeStaysWithinItsRect() {
        let path = FlameShape().path(in: Self.rect)
        let bounds = path.boundingRect

        #expect(!path.isEmpty)
        #expect(bounds.minX >= Self.rect.minX - 0.001)
        #expect(bounds.minY >= Self.rect.minY - 0.001)
        #expect(bounds.maxX <= Self.rect.maxX + 0.001)
        #expect(bounds.maxY <= Self.rect.maxY + 0.001)
    }

    @Test func liquidIsNearlyEmptyAtZeroLevel() {
        let bounds = StreakLiquidShape(level: 0, phase: 0).path(in: Self.rect).boundingRect

        // Only the small surface ripple at the base remains.
        #expect(bounds.height <= Self.rect.height * 0.2)
    }

    @Test func liquidFillsAtFullLevel() {
        let bounds = StreakLiquidShape(level: 1, phase: 0).path(in: Self.rect).boundingRect

        #expect(bounds.height >= Self.rect.height * 0.95)
    }

    @Test func liquidRisesWithLevel() {
        let low = StreakLiquidShape(level: 0.25, phase: 0).path(in: Self.rect).boundingRect.height
        let high = StreakLiquidShape(level: 0.75, phase: 0).path(in: Self.rect).boundingRect.height

        #expect(high > low)
    }

    @Test func liquidLevelClampsAboveOne() {
        let full = StreakLiquidShape(level: 1, phase: 0).path(in: Self.rect).boundingRect.height
        let overfull = StreakLiquidShape(level: 1.5, phase: 0).path(in: Self.rect).boundingRect.height

        // Values past full must not keep growing the fill.
        #expect(abs(overfull - full) <= 0.001)
    }
}
