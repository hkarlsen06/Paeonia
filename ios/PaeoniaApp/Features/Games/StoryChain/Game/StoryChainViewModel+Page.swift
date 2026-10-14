import Foundation

/// Who wrote a line and when, for the popover that opens on a tap.
nonisolated struct StoryChainLineInfo: Equatable, Sendable {
    let authorName: String
    let isMine: Bool
    let createdAt: Date
    /// The word this line had to use, when the previous line dared the writer.
    let usedDare: String?
}

// The page: the story as the page draws it, and the lines that write themselves in.
extension StoryChainViewModel {
    func lineInfo(for lineID: UUID) -> StoryChainLineInfo? {
        page.lines.first { $0.id == lineID }.map { line in
            StoryChainLineInfo(
                authorName: line.authorName,
                isMine: line.isMine,
                createdAt: line.createdAt,
                usedDare: line.usedDare
            )
        }
    }

    /// The page tells the view model that the line finished writing itself in. A
    /// line from the partner buzzes once, as it lands.
    func arrivalFinished(lineID: UUID) {
        guard arrivingLineID == lineID else { return }
        let isPartnerLine = arrivalPace == .partner
        arrivingLineID = nil
        if isPartnerLine {
            PaeoniaHaptics.partnerDrawingReceived()
        }
        recompute()
    }

    // MARK: - Building the page

    func makePage() -> StoryChainPageContent {
        guard let userID = currentUserID, let story else {
            return StoryChainPageContent(opening: nil, lines: [], ghost: nil, arrivingLineID: nil)
        }
        var lines = pageLines(of: story.story, userID: userID)
        // A line the partner sent live shows before Convex has it. The same line
        // from Convex then replaces it with the same id, so nothing moves.
        if let sent = liveSentLine {
            lines.append(pageLine(
                id: sent.lineID ?? UUID(),
                number: sent.number,
                text: sent.text,
                isMine: false,
                previousDare: story.story.lines.last?.dareWord,
                createdAt: partnerMessage?.receivedAt ?? now
            ))
        }
        return StoryChainPageContent(
            opening: story.story.openingText,
            lines: lines,
            ghost: partnerGhost,
            arrivingLineID: arrivingLineID,
            arrivalPace: arrivalPace
        )
    }

    private func pageLines(of story: RemoteStoryChainStory, userID: UUID) -> [StoryChainPageLine] {
        story.lines.enumerated().map { index, line in
            pageLine(
                id: line.id,
                number: line.number,
                text: line.text,
                isMine: line.authorUserID == userID,
                previousDare: index > 0 ? story.lines[index - 1].dareWord : nil,
                createdAt: line.createdAt
            )
        }
    }

    private func pageLine( // swiftlint:disable:this function_parameter_count
        id: UUID,
        number: Int,
        text: String,
        isMine: Bool,
        previousDare: String?,
        createdAt: Date
    ) -> StoryChainPageLine {
        StoryChainPageLine(
            id: id,
            number: number,
            text: text,
            isMine: isMine,
            // Only a dare the line really contains is underlined.
            usedDare: previousDare.flatMap { StoryChainRules.lineUses(text, dare: $0) ? $0 : nil },
            authorName: isMine ? participants.currentName : participants.partnerName,
            createdAt: createdAt
        )
    }

    // MARK: - Arrivals

    /// Starts one line writing itself in. `isMine` is a line this person just sent,
    /// which writes in a little faster. Both values change in the same update.
    func beginArrival(of lineID: UUID, isMine: Bool) {
        animatedLineIDs.insert(lineID)
        arrivingLineID = lineID
        arrivalPace = isMine ? .mine : .partner
    }

    /// The screen is open and it is this person's turn to write or name. The
    /// partner's newest line writes itself in once, whether it arrived while the
    /// screen was open or before it opened.
    func startArrivalIfNeeded() {
        guard isRunning, arrivingLineID == nil, phase == .writing || phase == .naming,
              let line = story?.story.lines.last, line.authorUserID != currentUserID,
              !animatedLineIDs.contains(line.id)
        else { return }
        beginArrival(of: line.id, isMine: false)
    }
}
