#if DEBUG
  import Foundation
  import SwiftUI
  import UIKit

  /// Board game scenarios. They run the real Connect Four, Dots and Boxes,
  /// Ultimate Tic-Tac-Toe and Ludo screens on in-memory dependencies.
  ///
  /// The cache holds a fixed server state, and the gateway fails every read of the
  /// games like a phone without a connection, so the cache is what the board
  /// shows. A move made here is saved in the in-memory queue and shows on the
  /// board, but nothing sends it and Robin never answers.
  @MainActor
  enum DeveloperBoardGamesScenarioFactory {
    /// Writes what the phone remembers before the screen opens: how far it showed
    /// the game, and a move that waits in the queue.
    static func seed(_ scenario: DeveloperScenario, dependencies: GamesDependencies) async {
      for setup in DeveloperBoardGamesFixture.setups(for: scenario) {
        if let shown = setup.shown {
          await dependencies.boardGamesCache.markShown(
            shown,
            kind: setup.kind,
            ownerUserID: DeveloperGamesFixture.me
          )
        }
        if let roll = setup.savedRoll() {
          await dependencies.boardGamesCache.saveLudoRoll(roll, ownerUserID: DeveloperGamesFixture.me)
        }
        if let payload = setup.queuedPayload() {
          await enqueueFailedMove(payload, dependencies: dependencies)
        }
      }
    }

    /// Queues a move the way a phone keeps it after a try without a connection,
    /// so the screen says "Saved on this phone".
    private static func enqueueFailedMove(
      _ payload: BoardGameMovePayload,
      dependencies: GamesDependencies
    ) async {
      let now = DeveloperScenarioFixture.now
      let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1, localCreatedAt: now)
      guard let request = try? BoardGamePendingWork.request(
        for: .move(payload),
        ownerUserID: DeveloperGamesFixture.me,
        operation: operation
      ) else { return }
      let store = dependencies.pendingOperationStore
      try? await store.enqueue(request)
      try? await store.markRetryableFailure(
        clientOperationID: operation.id,
        errorDescription: "NSURLErrorDomain -1009",
        nextRetryAt: nil,
        at: now
      )
    }
  }

  // MARK: - Screen

  /// One board game on its own screen, the way the hub opens it.
  @MainActor
  struct DeveloperBoardGamesScenarioView: View {
    let scenario: DeveloperScenario

    @ViewBuilder
    var body: some View {
      switch scenario.boardGame {
      case .connectFour:
        DeveloperBoardGameHost(scenario: scenario, makeHub: ConnectFourGame.hubModel)
      case .dotsAndBoxes:
        DeveloperBoardGameHost(scenario: scenario, makeHub: DotsAndBoxesGame.hubModel)
      case .ultimateTicTacToe:
        DeveloperBoardGameHost(scenario: scenario, makeHub: UltimateTicTacToeGame.hubModel)
      case .ludo:
        DeveloperBoardGameHost(scenario: scenario, makeHub: LudoGame.hubModel)
      case nil:
        EmptyView()
      }
    }
  }

  /// Builds the game's hub model on the scenario's dependencies and shows the
  /// screen that model opens, so the scenario uses the production wiring.
  @MainActor
  private struct DeveloperBoardGameHost<Board: BoardGameRules>: View {
    let scenario: DeveloperScenario
    let dependencies: GamesDependencies
    @State private var hub: BoardGameHubModel<Board>
    @State private var isReady = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(scenario: DeveloperScenario, makeHub: (GamesDependencies) -> BoardGameHubModel<Board>) {
      self.scenario = scenario
      let dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
      let hub = makeHub(dependencies)
      hub.configure(participants: DeveloperGamesFixture.participants)
      self.dependencies = dependencies
      _hub = State(initialValue: hub)
    }

    var body: some View {
      NavigationStack {
        if isReady, let screen = hub.screen(for: .game(hub.kind)) {
          screen
            .navigationDestination(for: GamesDestination.self) { destination in
              if let screen = hub.screen(for: destination) {
                screen
              }
            }
        } else {
          Color.paeoniaBackgroundPrimary
        }
      }
      .paeoniaTopBanner(bannerCenter)
      .task {
        await DeveloperBoardGamesScenarioFactory.seed(scenario, dependencies: dependencies)
        isReady = true
        guard scenario == .boardGameMarkEditor else { return }
        // The sheet opens over a board that has appeared, as it does from the toolbar.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        hub.game.openMarkEditor()
      }
    }
  }

  // MARK: - Gateway

  // The protocol is async, and these calls fail or answer at once.
  // swiftlint:disable async_without_await

  /// The board games gateway for scenarios. Reading the games fails like a phone
  /// without a connection, so the cache stays the state. Marks work: saving takes
  /// a moment, and the next read returns what was saved, so a mark drawn in a
  /// scenario shows on the pieces. "Past games" of Ultimate Tic-Tac-Toe holds the
  /// scenarios' won game, so the replay can be watched.
  actor DeveloperBoardGamesGateway: BoardGamesGateway {
    private var mine: RemoteBoardGameMark?

    func loadBoardGames() async throws -> RemoteBoardGames {
      throw URLError(.notConnectedToInternet)
    }

    func loadMarks() async throws -> RemoteBoardGameMarks {
      RemoteBoardGameMarks(userID: DeveloperGamesFixture.me, mine: mine, partner: nil)
    }

    func loadHistory(
      _ kind: GameKind,
      beforeGameNumber _: Int?,
      limit _: Int
    ) async throws -> RemoteBoardGameHistoryPage {
      guard kind == .ultimateTicTacToe else {
        return RemoteBoardGameHistoryPage(games: [], nextBeforeGameNumber: nil)
      }
      let game = RemoteBoardGameHistoryGame(
        gameNumber: 1,
        firstUserID: DeveloperGamesFixture.me,
        moves: DeveloperBoardGamesMoves.ultimateTicTacToeGame,
        winnerUserID: DeveloperGamesFixture.me,
        winLine: [2, 4, 6],
        stake: "Loser makes coffee",
        startedAt: DeveloperScenarioFixture.now.addingTimeInterval(-3_600),
        finishedAt: DeveloperScenarioFixture.now
      )
      return RemoteBoardGameHistoryPage(games: [game], nextBeforeGameNumber: nil)
    }

    func ensureGame(_: GameKind) async throws -> RemoteBoardGame {
      throw URLError(.notConnectedToInternet)
    }

    func makeMove(_: BoardGameMovePayload, operation _: SyncClientOperation) async throws -> RemoteBoardGame {
      throw URLError(.notConnectedToInternet)
    }

    func startRematch(_: BoardGameRematchPayload, operation _: SyncClientOperation) async throws -> RemoteBoardGame {
      throw URLError(.notConnectedToInternet)
    }

    func setMark(_ data: Data?) async throws -> Date? {
      try await Task.sleep(for: .milliseconds(700))
      guard let data else {
        mine = nil
        return nil
      }
      let now = DeveloperScenarioFixture.now
      mine = RemoteBoardGameMark(drawing: data.base64EncodedString(), updatedAt: now)
      return now
    }
  }
  // swiftlint:enable async_without_await

  // MARK: - Hidden photo

  /// The photo under a Dots and Boxes board: a generated picture, so the
  /// scenarios need no bundled image and no download.
  nonisolated struct DeveloperBoardPhotoProvider: MemoryMediaImageProviding {
    func imageData(for mediaAssetID: UUID?) async -> Data? {
      guard mediaAssetID == DeveloperBoardGamesFixture.photoAssetID else { return nil }
      return await MainActor.run { DeveloperBoardGamesFixture.photoData }
    }
  }

  extension DeveloperBoardGamesFixture {
    /// JPEG data of a sunset with a heart, clouds and bokeh dots. The board cuts it
    /// into sixteen boxes, and each box covers a different part of the picture.
    static let photoData: Data = {
      let side: CGFloat = 1_200
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
        let canvas = context.cgContext
        drawSky(in: canvas, side: side)
        drawBokeh(in: canvas, side: side)
        drawHeart(in: canvas, side: side)
        drawLandscape(in: canvas, side: side)
      }
      return image.jpegData(compressionQuality: 0.85) ?? Data()
    }()

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
      CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func drawSky(in canvas: CGContext, side: CGFloat) {
      let colors = [color(0.20, 0.16, 0.45), color(0.93, 0.43, 0.55), color(1.0, 0.74, 0.45)] as CFArray
      let space = CGColorSpaceCreateDeviceRGB()
      guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.4, 0.68]) else { return }
      canvas.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [])
      // The sun and its glow sit left of the middle peak.
      canvas.setFillColor(color(1.0, 0.93, 0.65, 0.25))
      canvas.fillEllipse(in: CGRect(x: side * 0.10, y: side * 0.28, width: side * 0.40, height: side * 0.40))
      canvas.setFillColor(color(1.0, 0.93, 0.65))
      canvas.fillEllipse(in: CGRect(x: side * 0.18, y: side * 0.36, width: side * 0.24, height: side * 0.24))
    }

    /// A round dot at a place on the picture, as fractions of its side.
    private struct Dot {
      let x: CGFloat
      let y: CGFloat
      let diameter: CGFloat
      let fill: CGColor
    }

    private static func drawBokeh(in canvas: CGContext, side: CGFloat) {
      let pink = color(0.98, 0.62, 0.75, 0.6)
      let teal = color(0.62, 0.90, 0.90, 0.6)
      let gold = color(1.0, 0.90, 0.55, 0.6)
      let lavender = color(0.80, 0.70, 1.0, 0.6)
      let dots = [
        Dot(x: 0.08, y: 0.10, diameter: 0.07, fill: pink), Dot(x: 0.30, y: 0.06, diameter: 0.04, fill: teal),
        Dot(x: 0.52, y: 0.12, diameter: 0.06, fill: gold), Dot(x: 0.74, y: 0.05, diameter: 0.05, fill: lavender),
        Dot(x: 0.90, y: 0.14, diameter: 0.08, fill: pink), Dot(x: 0.16, y: 0.22, diameter: 0.05, fill: gold),
        Dot(x: 0.62, y: 0.30, diameter: 0.04, fill: teal), Dot(x: 0.84, y: 0.34, diameter: 0.06, fill: gold),
        Dot(x: 0.44, y: 0.36, diameter: 0.03, fill: lavender), Dot(x: 0.06, y: 0.48, diameter: 0.06, fill: teal),
        Dot(x: 0.94, y: 0.52, diameter: 0.04, fill: pink), Dot(x: 0.22, y: 0.64, diameter: 0.03, fill: lavender),
      ]
      for dot in dots {
        canvas.setFillColor(dot.fill)
        canvas.fillEllipse(
          in: CGRect(x: side * dot.x, y: side * dot.y, width: side * dot.diameter, height: side * dot.diameter)
        )
      }
      // Three clouds.
      canvas.setFillColor(color(1, 1, 1, 0.45))
      for (x, y) in [(0.52, 0.42), (0.66, 0.50), (0.40, 0.22)] {
        canvas.fillEllipse(in: CGRect(x: side * x, y: side * y, width: side * 0.24, height: side * 0.05))
      }
    }

    private static func drawHeart(in canvas: CGContext, side: CGFloat) {
      // The heart is drawn in a unit square, then scaled and moved into the sky.
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
      let heart = UIBezierPath()
      heart.move(to: point(0.5, 0.95))
      heart.addCurve(to: point(0.05, 0.35), controlPoint1: point(0.35, 0.8), controlPoint2: point(0.05, 0.6))
      heart.addCurve(to: point(0.5, 0.25), controlPoint1: point(0.05, 0.05), controlPoint2: point(0.45, 0.05))
      heart.addCurve(to: point(0.95, 0.35), controlPoint1: point(0.55, 0.05), controlPoint2: point(0.95, 0.05))
      heart.addCurve(to: point(0.5, 0.95), controlPoint1: point(0.95, 0.6), controlPoint2: point(0.65, 0.8))
      heart.close()
      heart.apply(CGAffineTransform(translationX: side * 0.60, y: side * 0.14).scaledBy(x: side * 0.22, y: side * 0.22))
      canvas.setFillColor(color(1, 1, 1, 0.88))
      canvas.addPath(heart.cgPath)
      canvas.fillPath()
    }

    private static func drawLandscape(in canvas: CGContext, side: CGFloat) {
      let ranges: [(CGColor, [CGPoint])] = [
        (color(0.38, 0.30, 0.58), [
          CGPoint(x: 0, y: 0.72), CGPoint(x: 0.18, y: 0.55), CGPoint(x: 0.32, y: 0.68), CGPoint(x: 0.50, y: 0.50),
          CGPoint(x: 0.70, y: 0.70), CGPoint(x: 0.85, y: 0.58), CGPoint(x: 1, y: 0.70),
        ]),
        (color(0.22, 0.15, 0.38), [
          CGPoint(x: 0, y: 0.85), CGPoint(x: 0.25, y: 0.76), CGPoint(x: 0.55, y: 0.88), CGPoint(x: 0.80, y: 0.78),
          CGPoint(x: 1, y: 0.86),
        ]),
      ]
      for (fill, ridge) in ranges {
        canvas.setFillColor(fill)
        canvas.beginPath()
        canvas.move(to: CGPoint(x: 0, y: side))
        for point in ridge {
          canvas.addLine(to: CGPoint(x: side * point.x, y: side * point.y))
        }
        canvas.addLine(to: CGPoint(x: side, y: side))
        canvas.closePath()
        canvas.fillPath()
      }
    }
  }
#endif
