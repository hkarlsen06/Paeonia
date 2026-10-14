import Foundation

/// Story Chain's own message on its relay room. The writer's phone sends the
/// whole draft each time it changes (at most every 50 ms), and again when the
/// partner arrives, so the reader sees every letter as it is typed, deletions
/// included. Nothing in it is saved. The line itself goes through Convex.
///
/// The message never carries the dare word. The reader learns it when their
/// turn opens.
///
/// On the wire it is `{"story": "...", "number": 4, "text": "...", "last": false,
/// "line": "...", "sent": false}`. `line` is left out until the line is sent.
nonisolated struct StoryChainLiveMessage: GameLiveMessage, Equatable {
    static let game = "story_chain"

    /// The story the writer is in. The reader ignores any other story.
    let story: UUID
    /// The number of the line being written. The reader ignores a number that is
    /// not the next one on the page.
    let number: Int
    /// The draft as typed, at most 240 code points. A longer text is cut.
    let text: String
    /// The writer set the line to be the last one.
    let isLast: Bool
    /// The id of the line, set only when the line is sent. A Convex update with
    /// this line id then moves nothing on the reader's page.
    let lineID: UUID?
    /// The writer tapped Send. The reader's page plays the arrival right away.
    let sent: Bool

    init(story: UUID, number: Int, text: String, isLast: Bool, lineID: UUID? = nil, sent: Bool = false) {
        self.story = story
        self.number = number
        self.text = StoryChainRules.truncated(text)
        self.isLast = isLast
        self.lineID = lineID
        self.sent = sent
    }

    enum CodingKeys: String, CodingKey {
        case story
        case number
        case text
        case isLast = "last"
        case lineID = "line"
        case sent
    }

    /// A message from the partner's phone is cut to the same limit, so a long
    /// text from a bad sender cannot fill the page.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            story: try container.decode(UUID.self, forKey: .story),
            number: try container.decode(Int.self, forKey: .number),
            text: try container.decode(String.self, forKey: .text),
            isLast: try container.decode(Bool.self, forKey: .isLast),
            lineID: try container.decodeIfPresent(UUID.self, forKey: .lineID),
            sent: try container.decode(Bool.self, forKey: .sent)
        )
    }
}
