#if DEBUG
  import Foundation

  /// Answers Story Chain from the fixtures. Every move succeeds and changes
  /// nothing, because the screens already show a move the moment it is saved in
  /// the pending operations. Presence, invites and settings go to
  /// `DeveloperGamesGateway`.
  struct DeveloperStoryChainGateway: StoryChainGateway {
    typealias Fixture = DeveloperStoryChainFixture

    let scenario: DeveloperScenario
    private var games: DeveloperGamesGateway { DeveloperGamesGateway() }

    // The protocol is async, and these answer from the fixtures at once.
    // swiftlint:disable async_without_await

    // MARK: Shared Games calls

    func setSettings(playStyle: GamePlayStyle, language: GameLanguage) async throws -> RemoteGameSettings {
      try games.setSettings(playStyle: playStyle, language: language)
    }

    func markSettingsSeen() async throws -> RemoteGameSettings {
      try games.markSettingsSeen()
    }

    func loadOverview() async throws -> RemoteGamesOverview {
      try await games.loadOverview()
    }

    func setPresence(_ kind: GameKind, isPresent: Bool) async throws {
      try games.setPresence(kind, isPresent: isPresent)
    }

    func sendInvite(_ kind: GameKind) async throws -> RemoteInviteResult {
      try games.sendInvite(kind)
    }

    // MARK: Reading

    func ensureStoryChainGame() async throws -> RemoteEnsureStoryChainResult {
      RemoteEnsureStoryChainResult(gameID: Fixture.gameID, created: false)
    }

    func loadStoryChain() async throws -> RemoteStoryChainState {
      // With no opening lines on the phone, "Try again" has to stay offline.
      if scenario == .storyChainChooseOffline {
        throw URLError(.notConnectedToInternet)
      }
      return DeveloperStoryChainScenarios.state(for: scenario)
    }

    func loadStory(id: UUID) async throws -> RemoteStoryChainStory? {
      let state = DeveloperStoryChainScenarios.state(for: scenario)
      let stories = [state.currentStory, state.previousStory].compactMap(\.self) + Fixture.archivedStories()
      return stories.first { $0.id == id }
    }

    func loadStoryChainHistory(
      starredOnly: Bool,
      beforeStoryNumber: Int?,
      limit: Int
    ) async throws -> RemoteStoryChainHistoryPage {
      guard scenario != .storyChainHistoryEmpty else {
        return RemoteStoryChainHistoryPage(stories: [], nextBeforeStoryNumber: nil)
      }
      return Fixture.historyPage(starredOnly: starredOnly, before: beforeStoryNumber, limit: limit)
    }

    // MARK: Moves

    func startStory(
      _ start: StoryChainQueuedStart,
      operation _: SyncClientOperation
    ) async throws -> RemoteStartStoryResult {
      RemoteStartStoryResult(storyID: start.storyID, storyNumber: Fixture.storyNumber + 1)
    }

    func addStoryLine(
      _ line: StoryChainQueuedLine,
      operation _: SyncClientOperation
    ) async throws -> RemoteAddStoryLineResult {
      let written = DeveloperStoryChainScenarios.state(for: scenario).currentStory?.lines.count ?? 0
      return RemoteAddStoryLineResult(
        lineID: line.lineID,
        number: written + 1,
        storyState: line.isLast ? .titling : .writing
      )
    }

    func nameStory(
      _ name: StoryChainQueuedName,
      operation _: SyncClientOperation
    ) async throws -> RemoteNameStoryResult {
      RemoteNameStoryResult(storyID: name.storyID, title: name.title)
    }

    func markStorySeen(storyID _: UUID) async throws {}

    func setStoryStar(storyID: UUID, starred: Bool) async throws -> RemoteStoryStarResult {
      RemoteStoryStarResult(storyID: storyID, starred: starred)
    }

    // swiftlint:enable async_without_await
  }
#endif
