#if DEBUG
  import Foundation
  import PencilKit

  /// The hub with nothing waiting (`games-hub-quiet`). Every game the couple played waits for
  /// Robin, so "Today's pick" shows the daily catalog pick, and the tiles show
  /// what the couple made: the boards, Alex's drawing, a finished creature, the last Mind
  /// Meld words and the story so far. The couple played 31 days, the last 4 in a row.
  @MainActor
  enum DeveloperGamesHubQuiet {
    private static let hour: TimeInterval = 3_600

    /// When each game was last open, for the order of the small tiles.
    private static let lastPlayed: [GameKind: TimeInterval] = [
      .drawAndGuess: 1, .mindMeld: 3, .storyChain: 5, .connectFour: 26, .exquisiteCorpse: 30,
      .ludo: 50, .dotsAndBoxes: 75,
    ]

    static func overview(
      for scenario: DeveloperScenario,
      drawAndGuess state: RemoteDrawAndGuessState
    ) -> RemoteGamesOverview? {
      guard scenario == .gamesHubQuiet else { return nil }
      let now = DeveloperGamesFixture.now
      var overview = RemoteGamesOverview(drawAndGuess: state)
      overview.presence = GameKind.allCases.compactMap { kind in
        lastPlayed[kind].map {
          RemoteGamePresence(
            kind: kind,
            myPresent: false,
            partnerPresent: false,
            lastInviteAt: nil,
            lastPlayedAt: now.addingTimeInterval(-$0 * hour)
          )
        }
      }
      overview.playDays = RemoteGamePlayDays(
        streak: 4,
        total: 31,
        today: LockScreenCalendarDate(containing: now, in: .current)
      )
      return overview
    }

    /// Robin draws the body of creature 3, and creature 2 is finished and on the phone.
    static func configure(_ dependencies: inout GamesDependencies, for scenario: DeveloperScenario) {
      guard scenario == .gamesHubQuiet else { return }
      typealias Fixture = ExquisiteCorpseDeveloperFixture
      dependencies.exquisiteCorpseCache = InMemoryExquisiteCorpseCache(
        state: Fixture.partnerBodyTurn(), ownerUserID: Fixture.me
      )
      for index in 0..<ExquisiteCorpsePartKind.allCases.count {
        let assetID = Fixture.assetID(figure: 2, partIndex: index, isStrip: false)
        if let drawing = Fixture.drawing(forAsset: assetID) {
          dependencies.drawingStore.saveDownloadedDrawing(drawing.dataRepresentation(), mediaAssetID: assetID)
        }
      }
    }
  }
#endif
