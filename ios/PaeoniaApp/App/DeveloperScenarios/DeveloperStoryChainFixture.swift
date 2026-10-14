#if DEBUG
  import Foundation

  /// Deterministic Story Chain stories for the scenarios. Alex is the signed-in
  /// person and Robin is the partner. The story in progress is story 4, "The
  /// Lighthouse Key", and three older stories are finished. Every date counts
  /// from `DeveloperScenarioFixture.now`, so the screens look the same on every
  /// launch. The story text is sample content, not catalog copy.
  ///
  /// The text does not depend on who wrote a line, so one script serves every
  /// scenario. The starter writes the odd lines and the other person the even
  /// ones. Some lines give the next line a dare word, and the next line uses it.
  nonisolated enum DeveloperStoryChainFixture {
    static let me = DeveloperGamesFixture.me
    static let partner = DeveloperGamesFixture.partner
    static let now = DeveloperGamesFixture.now

    static let gameID = id(1, 0)
    /// The story in progress, and the story the reveal shows.
    static let storyNumber = 4

    static func storyID(_ number: Int) -> UUID {
      id(2, number)
    }

    static func lineID(story: Int, number: Int) -> UUID {
      id(3, story, number)
    }

    private static func id(_ kind: Int, _ number: Int, _ item: Int = 0) -> UUID {
      UUID(uuidString: String(format: "5c%02lx0000-0000-4000-8000-%04lx%08lx", kind, number, item)) ?? UUID()
    }

    struct Beat {
      let text: String
      /// The word this line gives to the next one.
      let dare: String?

      init(_ text: String, dare: String? = nil) {
        self.text = text
        self.dare = dare
      }
    }

    // MARK: States

    /// Story 4 in progress with its first `count` lines. Alex wrote line 1, so
    /// Alex writes the odd lines, and the turn is Alex's after an even count.
    static func writing(lines count: Int, version: Int = 1) -> RemoteStoryChainState {
      let turn = count.isMultiple(of: 2) ? me : partner
      return state(
        game(.writing, turn: turn, version: version),
        current: lighthouseStory(Array(lighthouse.prefix(count)), state: .writing, starter: me),
        words: turn == me ? words : nil
      )
    }

    /// Story 4 on line 20. Robin started it, so Alex writes the last line. Robin's
    /// line 19 dared Alex to use "tuesday".
    static func lastLine() -> RemoteStoryChainState {
      state(
        game(.writing, turn: me),
        current: lighthouseStory(lighthouse + lighthouseDetour, state: .writing, starter: partner),
        words: words
      )
    }

    /// Story 4 is written to its last line (line 13) and `namer` gives it a title.
    /// The starter wrote the last line, so the starter is the other person.
    static func titling(namedBy namer: UUID) -> RemoteStoryChainState {
      let starter = namer == me ? partner : me
      return state(
        game(.titling, turn: namer),
        current: lighthouseStory(lighthouse + [lighthouseEnding], state: .titling, starter: starter)
      )
    }

    /// Robin named story 4 and picks the next opening. Alex wrote the last line and
    /// has not seen the ending.
    static func finished() -> RemoteStoryChainState {
      state(
        game(.choosingOpening, turn: partner, storyCount: storyNumber, finishedCount: storyNumber),
        current: lighthouseStory(lighthouse + [lighthouseEnding], state: .finished, starter: me)
      )
    }

    /// Between stories. `turn` named story 3, so `turn` picks the next opening.
    /// Only the person who picks gets the opening lines.
    static func choosing(turn: UUID, openings: [RemoteStoryOpening]?) -> RemoteStoryChainState {
      state(
        game(.choosingOpening, turn: turn, storyCount: 3, finishedCount: 3),
        current: archivedStory(3, namedBy: turn),
        previous: archivedStory(2),
        openings: turn == me ? openings : nil
      )
    }

    private static func game(
      _ state: StoryChainGameState,
      turn: UUID,
      storyCount: Int = DeveloperStoryChainFixture.storyNumber,
      finishedCount: Int = 3,
      version: Int = 1
    ) -> RemoteStoryChainGame {
      RemoteStoryChainGame(
        id: gameID,
        state: state,
        turnUserID: turn,
        turnNumber: 11,
        currentStoryID: storyID(storyCount),
        storyCount: storyCount,
        finishedCount: finishedCount,
        turnStartedAt: now.addingTimeInterval(-1_200),
        version: version
      )
    }

    private static func state(
      _ game: RemoteStoryChainGame,
      current: RemoteStoryChainStory,
      previous: RemoteStoryChainStory? = nil,
      openings: [RemoteStoryOpening]? = nil,
      words: [RemoteStoryDareWord]? = nil
    ) -> RemoteStoryChainState {
      RemoteStoryChainState(
        userID: me,
        partnerUserID: partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        dataEpoch: "",
        game: game,
        currentStory: current,
        previousStory: previous ?? archivedStory(3),
        openingChoices: openings,
        wordChoices: words
      )
    }

    // MARK: Stories

    private struct StorySpec {
      var number: Int
      var opening: RemoteStoryOpening
      var title: String
      var beats: [Beat]
      var starter: UUID
      var startingAt: Date
      var state = StoryChainStoryState.finished
      var seenByMe = true
      var starred = false
    }

    private static func lighthouseStory(
      _ beats: [Beat],
      state: StoryChainStoryState,
      starter: UUID
    ) -> RemoteStoryChainStory {
      story(StorySpec(
        number: storyNumber,
        opening: opening,
        title: "The Lighthouse Key",
        beats: beats,
        starter: starter,
        startingAt: now.addingTimeInterval(-172_800),
        state: state,
        seenByMe: false
      ))
    }

    /// The person who names a finished story is the one who did not write its
    /// last line. These stories have 8 lines, so the starter names them.
    private static func story(_ spec: StorySpec) -> RemoteStoryChainStory {
      let lines = makeLines(of: spec)
      let lastWriter = lines.last?.authorUserID
      let isFinished = spec.state == .finished
      return RemoteStoryChainStory(
        id: storyID(spec.number),
        storyNumber: spec.number,
        starterUserID: spec.starter,
        openingID: spec.opening.openingID,
        openingText: spec.opening.text,
        state: spec.state,
        lines: lines,
        lastLineUserID: spec.state == .writing ? nil : lastWriter,
        title: isFinished ? spec.title : nil,
        titledByUserID: isFinished ? (lastWriter == me ? partner : me) : nil,
        finishedAt: isFinished ? lines.last.map { $0.createdAt.addingTimeInterval(1_800) } : nil,
        seenByMe: spec.seenByMe,
        starredByMe: spec.starred,
        createdAt: spec.startingAt,
        updatedAt: lines.last?.createdAt ?? spec.startingAt
      )
    }

    private static func makeLines(of spec: StorySpec) -> [RemoteStoryLine] {
      let other = spec.starter == me ? partner : me
      return spec.beats.enumerated().map { index, beat in
        let number = index + 1
        return RemoteStoryLine(
          id: lineID(story: spec.number, number: number),
          number: number,
          authorUserID: index.isMultiple(of: 2) ? spec.starter : other,
          text: beat.text,
          dareWord: beat.dare,
          createdAt: spec.startingAt.addingTimeInterval(Double(number) * 5_400 + Double(number % 3) * 1_200)
        )
      }
    }

    // MARK: Finished stories and "Our stories"

    /// A finished story from before story 4. `namer` overrides who started and
    /// so who named it.
    static func archivedStory(_ number: Int, namedBy namer: UUID? = nil) -> RemoteStoryChainStory {
      var spec = archiveSpec(number)
      if let namer {
        spec.starter = namer
      }
      return story(spec)
    }

    private static func archiveSpec(_ number: Int) -> StorySpec {
      switch number {
      case 3:
        StorySpec(
          number: 3,
          opening: RemoteStoryOpening(
            openingID: "goat_raincoat",
            text: "Every morning at seven, a goat in a yellow raincoat waited at the bus stop."
          ),
          title: "The Goat Who Was Expected",
          beats: goatBeats,
          starter: me,
          startingAt: now.addingTimeInterval(-4 * 86_400),
          starred: true
        )
      case 2:
        StorySpec(
          number: 2,
          opening: RemoteStoryOpening(
            openingID: "midnight_bakery",
            text: "The bakery on Maple Street only opened at midnight, and nobody knew who baked the bread."
          ),
          title: "Bread After Midnight",
          beats: bakeryBeats,
          starter: partner,
          startingAt: now.addingTimeInterval(-11 * 86_400)
        )
      default:
        StorySpec(
          number: 1,
          opening: RemoteStoryOpening(
            openingID: "lamp_post_scarves",
            text: "Overnight, somebody had knitted a scarf for every lamp post along the river."
          ),
          title: "Who Knitted the River?",
          beats: scarfBeats,
          starter: me,
          startingAt: now.addingTimeInterval(-24 * 86_400),
          starred: true
        )
      }
    }

    /// Every finished story before story 4, newest first.
    static func archivedStories() -> [RemoteStoryChainStory] {
      [3, 2, 1].map { archivedStory($0) }
    }

    static func historyItems() -> [RemoteStoryChainHistoryItem] {
      archivedStories().map { story in
        RemoteStoryChainHistoryItem(
          id: story.id,
          storyNumber: story.storyNumber,
          title: story.title ?? "",
          firstLine: story.openingText ?? story.lines.first?.text ?? "",
          lineCount: story.lines.count,
          finishedAt: story.finishedAt ?? story.updatedAt,
          starredByMe: story.starredByMe
        )
      }
    }

    /// The server's answer for a page: stories before the cursor, optionally only
    /// the starred ones.
    static func historyPage(starredOnly: Bool, before: Int?, limit: Int) -> RemoteStoryChainHistoryPage {
      let matching = historyItems().filter { item in
        (before.map { item.storyNumber < $0 } ?? true) && (!starredOnly || item.starredByMe)
      }
      let page = Array(matching.prefix(limit))
      return RemoteStoryChainHistoryPage(
        stories: page,
        nextBeforeStoryNumber: matching.count > limit ? page.last?.storyNumber : nil
      )
    }
  }
#endif
