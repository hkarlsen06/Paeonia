import Foundation

/// How close a guess came, as the reveal says it.
nonisolated enum ConsensioVerdict: Equatable, Sendable {
    /// 0 to 3 off.
    case spotOn
    /// 4 to 11 off.
    case soClose
    /// 12 to 19 off.
    case close
    /// 20 or more off.
    case far
}

/// The rules the phone and the server share (`backend/convex/lib/consensio.ts`).
nonisolated enum ConsensioRules {
    static let maxSpot = 100
    static let subjectLength = 2...60
    static let endLength = 1...24
    /// The real spot is "in the middle" from here to `100 - middleRange.lowerBound`.
    static let middleRange = 45...55

    /// One point less for every 4 off: 5 for 0 to 3 off, 0 from 20 off.
    static func points(distance: Int) -> Int {
        max(0, 5 - distance / 4)
    }

    static func verdict(distance: Int) -> ConsensioVerdict {
        switch distance {
        case ...3: .spotOn
        case ...11: .soClose
        case ...19: .close
        default: .far
        }
    }

    /// Trims and collapses every run of whitespace, line breaks included, to one space.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first problem with a topic the placer wrote, or nil when it can be placed.
    static func ownTopicIssue(subject: String, leftEnd: String, rightEnd: String) -> ConsensioTopicIssue? {
        let subject = normalized(subject)
        let left = normalized(leftEnd)
        let right = normalized(rightEnd)
        // The server counts Unicode code points.
        if !subjectLength.contains(subject.unicodeScalars.count) { return .subject }
        if !endLength.contains(left.unicodeScalars.count) || !endLength.contains(right.unicodeScalars.count) {
            return .end
        }
        if left.lowercased() == right.lowercased() { return .sameEnds }
        // Control, private-use and unassigned code points, which the server refuses.
        let refused: [Unicode.GeneralCategory] = [.control, .privateUse, .unassigned]
        let scalars = (subject + left + right).unicodeScalars
        if scalars.contains(where: { refused.contains($0.properties.generalCategory) }) {
            return .characters
        }
        return nil
    }
}

nonisolated enum ConsensioTopicIssue: Equatable, Sendable {
    case subject
    case end
    case sameEnds
    case characters
}
