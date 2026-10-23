import Foundation

/// Works out the phase from the server's state and this phone's unsent moves.
/// It reads no clock and no network.
///
/// The server's game says whose turn it is and what comes next. The resolver
/// then plays this person's queued moves on top, one by one, the way the server
/// will: a start puts this person on line 1 of the new story, a line passes the
/// turn to the partner, a last line passes it to the partner for naming, and a
/// name passes the choice of the next opening to this person. A move the server
/// already has, found by its id, is skipped.
///
/// A finished story this person has not moved past comes first. A mark that
/// waits on this phone counts as moved past, and so does naming the story.
/// So the partner who names a story never gets `finished` from here, and the
/// screen shows that reveal itself from `StoryChainResolution.story`.
///
/// `waitingToSync` is for a game and a story that disagree, such as a game that
/// is writing with no story in the state. It is brief, because the next read
/// from the server fixes it.
nonisolated struct StoryChainResolver: Sendable {
    let userID: UUID

    func resolve(
        state: RemoteStoryChainState?,
        settings: RemoteGameSettings?,
        pending: StoryChainPendingWork
    ) -> StoryChainResolution {
        let waiting = pending.hasMoveWaiting
        guard let state else {
            return StoryChainResolution(phase: .loading, story: nil, isWaitingToSend: waiting)
        }
        guard settings != nil else {
            return StoryChainResolution(phase: .needsSetup, story: nil, isWaitingToSend: waiting)
        }
        guard let game = state.game else {
            return StoryChainResolution(phase: .preparing, story: nil, isWaitingToSend: waiting)
        }

        var timeline = Timeline(state: state, game: game, userID: userID)
        timeline.apply(pending, game: game)
        let turnPhase = timeline.phase
        // The partner may have named a story and started the next one while this
        // person was away. The ending comes first.
        if let unseen = timeline.stories.last(where: { $0.story.state == .finished && !$0.story.seenByMe }) {
            return StoryChainResolution(
                phase: .finished(storyID: unseen.id),
                story: unseen,
                isWaitingToSend: waiting,
                turnPhase: turnPhase
            )
        }
        return StoryChainResolution(phase: turnPhase, story: timeline.stories.last, isWaitingToSend: waiting)
    }

    /// It is this person's turn to write or to name the story once the partner's line
    /// hands it over, also while the last story's reveal is still on screen. The opening
    /// always goes to whoever named the last story or started the game, and line 1 to
    /// whoever picked the opening, so neither counts as a handover.
    func attention(state: RemoteStoryChainState?, pending: StoryChainPendingWork) -> GameAttention {
        guard let state, let game = state.game else { return GameAttention() }
        var timeline = Timeline(state: state, game: game, userID: userID)
        timeline.apply(pending, game: game)
        guard timeline.phase == .writing || timeline.phase == .naming,
              let line = timeline.stories.last?.story.lines.last, line.authorUserID != userID
        else {
            return GameAttention()
        }
        return GameAttention(turn: "line \(line.id)")
    }

    /// What this phone tells the partner's phone through the relay room.
    static func liveRole(for phase: StoryChainPhase) -> WidgetLivePresence.Role {
        switch phase {
        case .writing: .drawing
        case .waitingForLine: .watching
        case .chooseOpening, .naming: .choosing
        case .finished: .result
        default: .present
        }
    }

    // MARK: Timeline

    /// The server's last two stories and the game's state, moved forward by this
    /// person's queued moves.
    private struct Timeline {
        let userID: UUID
        /// Oldest first. The last one is the current story.
        var stories: [StoryChainEffectiveStory]
        var gameState: StoryChainGameState
        var isMyTurn: Bool

        init(state: RemoteStoryChainState, game: RemoteStoryChainGame, userID: UUID) {
            self.userID = userID
            stories = [state.previousStory, state.currentStory].compactMap { $0 }.map {
                StoryChainEffectiveStory(story: $0)
            }
            gameState = game.state
            isMyTurn = game.turnUserID == userID
        }

        /// The phase the game is in for this person.
        var phase: StoryChainPhase {
            switch (gameState, stories.last?.story.state) {
            case (.choosingOpening, nil), (.choosingOpening, .some(.finished)):
                isMyTurn ? .chooseOpening : .waitingForOpening
            case (.writing, .some(.writing)):
                isMyTurn ? .writing : .waitingForLine
            case (.titling, .some(.titling)):
                isMyTurn ? .naming : .waitingForName
            default:
                .waitingToSync
            }
        }

        mutating func apply(_ pending: StoryChainPendingWork, game: RemoteStoryChainGame) {
            for index in stories.indices {
                applyMoves(of: pending, toStoryAt: index)
            }
            for start in pending.starts where start.gameID == game.id && !hasStory(start.storyID) {
                begin(start, game: game)
                applyMoves(of: pending, toStoryAt: stories.count - 1)
            }
            for index in stories.indices where pending.seenStoryIDs.contains(stories[index].id) {
                stories[index].story.seenByMe = true
            }
        }

        private func hasStory(_ storyID: UUID) -> Bool {
            stories.contains { $0.id == storyID }
        }

        /// A story this person started on this phone. They write its first line.
        private mutating func begin(_ start: StoryChainQueuedStart, game: RemoteStoryChainGame) {
            let newest = stories.map(\.story.storyNumber).max() ?? 0
            let story = RemoteStoryChainStory(
                id: start.storyID,
                storyNumber: max(game.storyCount, newest) + 1,
                starterUserID: userID,
                openingID: start.openingID,
                openingText: start.openingText,
                state: .writing,
                lines: [],
                lastLineUserID: nil,
                title: nil,
                titledByUserID: nil,
                finishedAt: nil,
                seenByMe: false,
                createdAt: start.createdAt,
                updatedAt: start.createdAt
            )
            stories.append(StoryChainEffectiveStory(story: story, isOnlyOnThisPhone: true))
            gameState = .writing
            isMyTurn = true
        }

        private mutating func applyMoves(of pending: StoryChainPendingWork, toStoryAt index: Int) {
            let storyID = stories[index].id
            let knownLineIDs = Set(stories[index].story.lines.map(\.id))
            for line in pending.lines where line.storyID == storyID && !knownLineIDs.contains(line.lineID) {
                // The server refuses a line on a story that is not being written.
                guard stories[index].story.state == .writing,
                      stories[index].story.lines.count < StoryChainRules.maxLines
                else {
                    break
                }
                addLine(line, toStoryAt: index)
            }
            for name in pending.names where name.storyID == storyID {
                applyName(name, toStoryAt: index)
            }
        }

        private mutating func addLine(_ queued: StoryChainQueuedLine, toStoryAt index: Int) {
            let line = RemoteStoryLine(
                id: queued.lineID,
                number: stories[index].story.lines.count + 1,
                authorUserID: userID,
                text: queued.text,
                dareWord: queued.dareWord,
                createdAt: queued.createdAt
            )
            stories[index].story.lines.append(line)
            stories[index].unsentLineIDs.insert(queued.lineID)
            if queued.isLast {
                stories[index].story.state = .titling
                stories[index].story.lastLineUserID = userID
            }
            gameState = queued.isLast ? .titling : .writing
            isMyTurn = false
        }

        /// Naming finishes the story. The namer has seen it, and starts the next one.
        private mutating func applyName(_ name: StoryChainQueuedName, toStoryAt index: Int) {
            guard stories[index].story.state == .titling else {
                return
            }
            stories[index].story.state = .finished
            stories[index].story.title = name.title
            stories[index].story.titledByUserID = userID
            stories[index].story.seenByMe = true
            stories[index].hasUnsentName = true
            gameState = .choosingOpening
            isMyTurn = true
        }
    }
}
