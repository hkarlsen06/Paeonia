import Foundation

extension RemoteStoryChainStory {
    /// The story as the page draws it, for a finished story outside the game
    /// screen. `youName` is the name for my own lines.
    nonisolated func pageContent(currentUserID: UUID?, youName: String, partnerName: String) -> StoryChainPageContent {
        var previousDare: String?
        var pageLines: [StoryChainPageLine] = []
        for line in lines {
            let isMine = line.authorUserID == currentUserID
            pageLines.append(StoryChainPageLine(
                id: line.id,
                number: line.number,
                text: line.text,
                isMine: isMine,
                // Only a dare the line really contains is underlined.
                usedDare: previousDare.flatMap { StoryChainRules.lineUses(line.text, dare: $0) ? $0 : nil },
                authorName: isMine ? youName : partnerName,
                createdAt: line.createdAt
            ))
            previousDare = line.dareWord
        }
        return StoryChainPageContent(opening: openingText, lines: pageLines, ghost: nil, arrivingLineID: nil)
    }

    /// How many dare words a following line used.
    nonisolated var usedDareCount: Int {
        zip(lines, lines.dropFirst()).count { line, next in
            line.dareWord.map { StoryChainRules.lineUses(next.text, dare: $0) } == true
        }
    }
}
