import Foundation

/// The couple's game language. It decides which decoy letters appear.
nonisolated enum DrawAndGuessLanguage: String, CaseIterable, Codable, Sendable {
    case en
    case nb

    /// Relative chance of each letter as a decoy. English follows ordinary
    /// English text. Norwegian follows ordinary Norwegian text, with Æ, Ø and Å
    /// raised so the Norwegian letters show up in a game.
    var decoyWeights: [(letter: Character, weight: Double)] {
        switch self {
        case .en:
            Self.englishWeights
        case .nb:
            Self.norwegianWeights
        }
    }

    var alphabet: Set<Character> {
        Set(decoyWeights.map(\.letter))
    }

    private static let englishWeights: [(letter: Character, weight: Double)] = [
        ("E", 12.7), ("T", 9.1), ("A", 8.2), ("O", 7.5), ("I", 7.0), ("N", 6.7),
        ("S", 6.3), ("H", 6.1), ("R", 6.0), ("D", 4.3), ("L", 4.0), ("C", 2.8),
        ("U", 2.8), ("M", 2.4), ("W", 2.4), ("F", 2.2), ("G", 2.0), ("Y", 2.0),
        ("P", 1.9), ("B", 1.5), ("V", 1.0), ("K", 0.8), ("J", 0.15), ("X", 0.15),
        ("Q", 0.1), ("Z", 0.07)
    ]

    private static let norwegianWeights: [(letter: Character, weight: Double)] = [
        ("E", 15.0), ("N", 7.5), ("R", 7.3), ("T", 7.0), ("A", 6.3), ("S", 6.0),
        ("I", 5.8), ("L", 5.2), ("O", 4.8), ("D", 4.6), ("K", 3.9), ("G", 3.7),
        ("M", 3.3), ("V", 2.4), ("F", 2.0), ("U", 1.9), ("H", 2.2), ("P", 1.7),
        ("B", 1.6), ("J", 1.3), ("Y", 0.9), ("C", 0.1), ("W", 0.1), ("X", 0.1),
        ("Z", 0.05), ("Q", 0.02),
        ("Å", 2.0), ("Ø", 2.0), ("Æ", 1.5)
    ]
}
