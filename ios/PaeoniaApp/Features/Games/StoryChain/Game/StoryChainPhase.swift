import Foundation

/// Where the person is in the game right now. Each case is one screen state.
nonisolated enum StoryChainPhase: Equatable, Sendable {
    /// Nothing is cached yet and the first read has not finished.
    case loading
    /// The couple has not picked a play style and language yet.
    case needsSetup
    /// The couple's game does not exist yet and is being created.
    case preparing
    /// It is this person's turn to pick an opening and start a story.
    case chooseOpening
    /// This person writes the next line.
    case writing
    /// The partner writes the next line.
    case waitingForLine
    /// The partner is picking an opening for the next story.
    case waitingForOpening
    /// This person gives the finished story a title.
    case naming
    /// The partner gives the finished story a title.
    case waitingForName
    /// A finished story this person has not moved past. Shows the reveal.
    case finished(storyID: UUID)
    /// The game and the story disagree. See `StoryChainResolver` for when.
    case waitingToSync
}

/// A story as the screen shows it: the server's story with this phone's queued
/// moves applied on top.
nonisolated struct StoryChainEffectiveStory: Equatable, Identifiable, Sendable {
    var story: RemoteStoryChainStory
    /// The lines that are only on this phone.
    var unsentLineIDs: Set<UUID> = []
    /// The story was started on this phone and the server has not heard of it.
    var isOnlyOnThisPhone = false
    /// The title is queued and the server does not have it yet. `finishedAt` is
    /// nil until the server answers.
    var hasUnsentName = false

    var id: UUID { story.id }

    /// A move of this story is saved on this phone and not on the server yet.
    var isWaitingToSend: Bool {
        isOnlyOnThisPhone || hasUnsentName || !unsentLineIDs.isEmpty
    }

    func isUnsent(_ line: RemoteStoryLine) -> Bool {
        unsentLineIDs.contains(line.id)
    }
}

nonisolated struct StoryChainResolution: Equatable, Sendable {
    let phase: StoryChainPhase
    /// The story the phase is about, with unsent moves applied. For `finished` it
    /// is the finished story. Otherwise it is the newest story, which is finished
    /// while an opening is chosen. Nil before the first story.
    let story: StoryChainEffectiveStory?
    /// A move is saved on this phone and not on the server yet.
    let isWaitingToSend: Bool
    /// The phase once the person moves on from a finished story, or `phase` when
    /// no finished story waits. Whose turn the hub shows comes from this. It is
    /// never `.finished`.
    let turnPhase: StoryChainPhase

    init(
        phase: StoryChainPhase,
        story: StoryChainEffectiveStory?,
        isWaitingToSend: Bool,
        turnPhase: StoryChainPhase? = nil
    ) {
        self.phase = phase
        self.story = story
        self.isWaitingToSend = isWaitingToSend
        self.turnPhase = turnPhase ?? phase
    }
}
