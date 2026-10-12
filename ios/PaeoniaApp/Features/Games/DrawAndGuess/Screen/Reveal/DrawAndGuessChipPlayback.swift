import Foundation

/// How the drawer's chips appear when the round ended before they opened the game.
nonisolated enum DrawAndGuessChipPlayback {
    static let gap: TimeInterval = 0.5
    static let longestSequence: TimeInterval = 3

    /// Half a second apart, squeezed so the whole sequence takes 3 seconds at most.
    static func interval(chipCount: Int) -> TimeInterval {
        guard chipCount > 0 else { return 0 }
        return min(gap, longestSequence / Double(chipCount))
    }
}
