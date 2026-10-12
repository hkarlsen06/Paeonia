import Foundation

/// SplitMix64. The same seed gives the same numbers on every phone and every
/// OS version, unlike `SystemRandomNumberGenerator` and `Hasher`.
nonisolated struct DrawAndGuessSeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Turns the text into a number with FNV-1a, which never changes.
    init(seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }

    /// A number in `0..<bound`. Fixed arithmetic, so it never changes.
    mutating func nextIndex(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    /// A number in `0..<1`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
