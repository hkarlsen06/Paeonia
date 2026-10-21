#if DEBUG
  import Foundation
  import PencilKit
  import UIKit

  /// Deterministic server states and drawings for the Games scenarios. Alex is
  /// the signed-in person and Robin is the partner. Every date counts from
  /// `DeveloperScenarioFixture.now`, so the screens look the same on every launch.
  enum DeveloperGamesFixture {
    nonisolated static let gameID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let roundID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let nextRoundID = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002") ?? UUID()
    nonisolated static let assetID = UUID(uuidString: "cccccccc-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let me = DeveloperScenarioFixture.currentUserID
    nonisolated static let partner = DeveloperScenarioFixture.partnerUserID
    nonisolated static let now = DeveloperScenarioFixture.now

    static let participants = GameParticipants(
      currentUserID: me,
      coupleID: DeveloperScenarioFixture.coupleID,
      partnerName: "Robin",
      currentName: "Alex"
    )

    // MARK: Pieces

    static func settings(by user: UUID = me) -> RemoteGameSettings {
      RemoteGameSettings(
        coupleID: DeveloperScenarioFixture.coupleID,
        playStyle: .against,
        language: .en,
        updatedByUserID: user,
        createdAt: now.addingTimeInterval(-86_400),
        updatedAt: now.addingTimeInterval(-86_400)
      )
    }

    static func game(
      state: DrawAndGuessGameState,
      turn: UUID,
      roundID: UUID? = roundID
    ) -> RemoteDrawAndGuessGame {
      RemoteDrawAndGuessGame(
        id: gameID,
        kind: "draw_and_guess",
        state: state,
        turnUserID: turn,
        turnNumber: 4,
        currentRoundID: roundID,
        sharedPoints: 13,
        myPoints: 8,
        partnerPoints: 5,
        turnStartedAt: now.addingTimeInterval(-600),
        version: 9,
        createdAt: now.addingTimeInterval(-86_400),
        updatedAt: now.addingTimeInterval(-600)
      )
    }

    static func round(
      id: UUID = roundID,
      state: DrawAndGuessRoundState,
      drawer: UUID,
      word: String = "umbrella",
      hasDrawing: Bool = false,
      attempts: [(text: String, correct: Bool)] = [],
      solveMs: Int? = nil,
      speedBonus: Int = 0,
      firstTryBonus: Int = 0,
      hintsUsed: Int = 0,
      personalBest: Bool = false,
      /// The people who already moved past the result, as the server records it.
      resultSeenBy: Set<UUID> = [],
      guesserHasSeenIt: Bool = false
    ) -> RemoteDrawAndGuessRound {
      let guesser = drawer == me ? partner : me
      let finished = state == .solved || state == .missed
      return RemoteDrawAndGuessRound(
        id: id,
        roundNumber: 3,
        drawerUserID: drawer,
        guesserUserID: guesser,
        state: state,
        difficulty: .medium,
        word: word,
        points: 2,
        drawingMediaAssetID: hasDrawing ? assetID : nil,
        drawingSubmittedAt: hasDrawing ? now.addingTimeInterval(-900) : nil,
        startedAt: now.addingTimeInterval(-1_200),
        guesserFirstSeenAt: solveMs == nil && !guesserHasSeenIt ? nil : now.addingTimeInterval(-600),
        endedAt: finished ? now.addingTimeInterval(-580) : nil,
        solveMs: solveMs,
        speedBonus: speedBonus,
        firstTryBonus: firstTryBonus,
        hintsUsed: hintsUsed,
        personalBest: personalBest,
        drawerResultSeenAt: resultSeenBy.contains(drawer) ? now.addingTimeInterval(-300) : nil,
        guesserResultSeenAt: resultSeenBy.contains(guesser) ? now.addingTimeInterval(-300) : nil,
        attempts: attempts.enumerated().map { index, attempt in
          RemoteDrawAndGuessAttempt(
            id: UUID(uuidString: "dddddddd-0000-4000-8000-00000000000\(index + 1)") ?? UUID(),
            userID: guesser,
            text: attempt.text,
            correct: attempt.correct,
            createdAt: now.addingTimeInterval(-800 + Double(index) * 20)
          )
        }
      )
    }

    nonisolated static let choices = [
      RemoteDrawAndGuessChoice(difficulty: .easy, wordID: "en-easy-pizza", word: "pizza", points: 1),
      RemoteDrawAndGuessChoice(difficulty: .medium, wordID: "en-medium-umbrella", word: "umbrella", points: 2),
      RemoteDrawAndGuessChoice(difficulty: .hard, wordID: "en-hard-volcano", word: "volcano", points: 3),
    ]

    static func state(
      settings: RemoteGameSettings?,
      game: RemoteDrawAndGuessGame?,
      round: RemoteDrawAndGuessRound? = nil,
      recentRounds: [RemoteDrawAndGuessRound] = [],
      choices: [RemoteDrawAndGuessChoice]? = nil,
      partnerIsHere: Bool = false
    ) -> RemoteDrawAndGuessState {
      RemoteDrawAndGuessState(
        userID: me,
        partnerUserID: partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        dataEpoch: "",
        settings: settings,
        game: game,
        currentRound: round,
        recentRounds: recentRounds,
        choices: choices,
        myPresent: false,
        partnerPresent: partnerIsHere,
        lastInviteAt: nil
      )
    }

    // MARK: Drawing

    /// An umbrella at the canonical canvas size, drawn in three strokes with
    /// real time offsets, so the replay has a pace to follow.
    static func umbrella() -> PKDrawing {
      let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
      let canopy = (0...40).map { step -> CGPoint in
        let angle = Double.pi + Double.pi * Double(step) / 40
        return CGPoint(x: 160 + 105 * cos(angle), y: 150 + 90 * sin(angle))
      }
      let ribs: [CGPoint] = [
        CGPoint(x: 55, y: 150), CGPoint(x: 100, y: 138), CGPoint(x: 160, y: 150), CGPoint(x: 220, y: 138),
        CGPoint(x: 265, y: 150),
      ]
      let handle = [CGPoint(x: 160, y: 150), CGPoint(x: 160, y: 240)]
        + (0...12).map { step -> CGPoint in
          // The hook curves down and to the right from the end of the handle.
          let angle = Double.pi - Double.pi * Double(step) / 12
          return CGPoint(x: 175 + 15 * cos(angle), y: 240 + 15 * sin(angle))
        }
      return PKDrawing(strokes: [
        stroke(canopy, color: .paeoniaAccentPrimary, startsAt: base),
        stroke(ribs, color: .paeoniaInkLavender, startsAt: base.addingTimeInterval(4)),
        stroke(handle, color: .paeoniaWidgetDrawing, startsAt: base.addingTimeInterval(7)),
      ])
    }

    private static func stroke(_ points: [CGPoint], color: UIColor, startsAt date: Date) -> PKStroke {
      let controlPoints = points.enumerated().map { index, point in
        PKStrokePoint(
          location: point,
          timeOffset: Double(index) * 0.05,
          size: CGSize(width: 6, height: 6),
          opacity: 1,
          force: 1,
          azimuth: 0,
          altitude: .pi / 2
        )
      }
      return PKStroke(
        ink: PKInk(.pen, color: color),
        path: PKStrokePath(controlPoints: controlPoints, creationDate: date)
      )
    }
  }
#endif
