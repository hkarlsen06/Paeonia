import Foundation
@testable import PaeoniaApp

/// The words the fake server draws from and the rules a custom word follows.
extension SimServer {
    static let catalog: [GameLanguage: [DrawAndGuessDifficulty: [(id: String, text: String)]]] = [
        .en: [
            .easy: [("cat", "cat"), ("sun", "sun"), ("tree", "tree"), ("fish", "fish"), ("ice-cream", "ice cream")],
            .medium: [("umbrella", "umbrella"), ("hot-dog", "hot dog"), ("rocket", "rocket"), ("guitar", "guitar")],
            .hard: [("volcano", "volcano"), ("pirate-ship", "pirate ship"), ("lighthouse", "lighthouse")],
        ],
        .nb: [
            .easy: [("sol", "sol"), ("maane", "måne"), ("katt", "katt"), ("aal", "ål")],
            .medium: [("brunost", "brunost"), ("fjord", "fjord"), ("isbjorn", "isbjørn")],
            .hard: [("nordlys", "nordlys"), ("aerfugl", "ærfugl"), ("vaffel-jern", "vaffel jern")],
        ],
    ]

    static func normalizeWordText(_ input: String) -> String {
        input.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// `normalizeCustomWord`.
    static func normalizeCustomWord(_ input: String) throws -> String {
        let word = normalizeWordText(input)
        let parts = word.split(separator: " ", omittingEmptySubsequences: false)
        let letters = word.filter { $0 != " " }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzæøå")
        guard parts.count <= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(allowed.contains) }),
              (2...20).contains(letters.count)
        else {
            throw fail("23514", "custom word must be 2 to 20 letters in at most three words")
        }
        return word
    }
}
