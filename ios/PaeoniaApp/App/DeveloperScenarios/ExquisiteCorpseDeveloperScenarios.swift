#if DEBUG
  import Foundation
  import PencilKit
  import SwiftUI

  extension DeveloperScenario {
    /// A hub scenario runs the real tabs, so the card sits next to Draw & Guess's.
    var isExquisiteCorpseHub: Bool {
      switch self {
      case .exquisiteCorpseHubYourTurn, .exquisiteCorpseHubPartnerDrawing, .exquisiteCorpseHubReveal,
        .exquisiteCorpseHubNotStarted:
        true
      default:
        false
      }
    }

    /// A scenario that opens one Exquisite corpse screen on its own.
    var isExquisiteCorpseScreen: Bool {
      switch self {
      case .exquisiteCorpseDrawHead, .exquisiteCorpseDrawBody, .exquisiteCorpseDrawLegs, .exquisiteCorpseWaiting,
        .exquisiteCorpseWatching, .exquisiteCorpseHandoff, .exquisiteCorpseWaitingToSync, .exquisiteCorpseReveal,
        .exquisiteCorpseRevealLoading, .exquisiteCorpseHistory, .exquisiteCorpseHistoryEmpty,
        .exquisiteCorpseHistoryStarred, .exquisiteCorpseHistoryDetail:
        true
      default:
        false
      }
    }
  }

  /// Exquisite corpse scenarios. They run the real hub model, game screen and
  /// "Our creatures" on in-memory dependencies, so every phase can be reached
  /// without a partner, a network, or the Convex backend.
  ///
  /// The cache holds a fixed server state. The pending operations are in memory,
  /// so a part sent here changes the screen the way it does on an offline phone.
  /// Robin's phone is a script on the relay connection (`ExquisiteCorpseDeveloperConnection`).
  @MainActor
  enum ExquisiteCorpseDeveloperScenarioFactory {
    /// A scenario's fixed server state.
    static func state( // swiftlint:disable:this cyclomatic_complexity
      for scenario: DeveloperScenario
    ) -> RemoteExquisiteCorpseState {
      typealias Fixture = ExquisiteCorpseDeveloperFixture
      switch scenario {
      case .exquisiteCorpseHubYourTurn:
        return Fixture.bodyTurn(figuresFinished: 12)
      case .exquisiteCorpseHubPartnerDrawing:
        return Fixture.partnerLegsTurn()
      case .exquisiteCorpseHubReveal, .exquisiteCorpseReveal, .exquisiteCorpseRevealLoading:
        return Fixture.unseenReveal()
      case .exquisiteCorpseHubNotStarted:
        return Fixture.notStarted()
      case .exquisiteCorpseDrawHead:
        return Fixture.headTurn()
      case .exquisiteCorpseDrawBody:
        return Fixture.bodyTurn()
      case .exquisiteCorpseDrawLegs, .exquisiteCorpseWaitingToSync:
        return Fixture.legsTurn()
      case .exquisiteCorpseWaiting, .exquisiteCorpseWatching, .exquisiteCorpseHandoff:
        return Fixture.partnerBodyTurn()
      case .exquisiteCorpseHistoryEmpty:
        return Fixture.headTurn()
      default:
        // The history scenarios: twelve finished creatures, and Alex starts the next one.
        return Fixture.state(game: Fixture.game(figure: 13, partIndex: 0, turn: Fixture.me, figuresFinished: 12))
      }
    }

    /// Robin has the game open in the hub scenario that says so.
    private static func partnerIsHere(in scenario: DeveloperScenario) -> Bool {
      scenario == .exquisiteCorpseHubPartnerDrawing
    }

    /// Sets the Exquisite corpse fields of a scenario's dependencies. The shared
    /// cache is replaced by one whose overview has the game's presence, and its
    /// Draw & Guess state stays as the scenario factory made it.
    static func configure(_ dependencies: inout GamesDependencies, for scenario: DeveloperScenario) {
      guard scenario.isExquisiteCorpseHub || scenario.isExquisiteCorpseScreen else { return }
      typealias Fixture = ExquisiteCorpseDeveloperFixture
      dependencies.cache = InMemoryGamesCache(
        state: DeveloperGamesScenarioFactory.state(for: scenario),
        overview: Fixture.overview(partnerIsHere: partnerIsHere(in: scenario)),
        ownerUserID: Fixture.me
      )
      let cache = InMemoryExquisiteCorpseCache(state: state(for: scenario), ownerUserID: Fixture.me)
      dependencies.exquisiteCorpseCache = cache
      dependencies.exquisiteCorpseGateway = ExquisiteCorpseDeveloperGateway(
        historyIsEmpty: scenario == .exquisiteCorpseHistoryEmpty
      )
      dependencies.drawingTransfer = ExquisiteCorpseDeveloperDrawingTransfer(
        stallsDownloads: scenario == .exquisiteCorpseRevealLoading
      )
      seedDrawings(into: dependencies.drawingStore, for: scenario)
      dependencies.makeExquisiteCorpseLive = { coupleID in
        makeLive(for: scenario, coupleID: coupleID, cache: cache)
      }
    }

    /// The files already on the phone. A strip or a part the scenario wants to load
    /// stays out, and the transfer serves it.
    private static func seedDrawings(into store: any GameDrawingStoring, for scenario: DeveloperScenario) {
      typealias Fixture = ExquisiteCorpseDeveloperFixture
      func keep(figure: Int, partIndex: Int, isStrip: Bool) {
        let assetID = Fixture.assetID(figure: figure, partIndex: partIndex, isStrip: isStrip)
        guard let drawing = Fixture.drawing(forAsset: assetID) else { return }
        store.saveDownloadedDrawing(drawing.dataRepresentation(), mediaAssetID: assetID)
      }
      switch scenario {
      case .exquisiteCorpseDrawBody:
        // Robin's head strip, for the strip above the canvas.
        keep(figure: 2, partIndex: 0, isStrip: true)
      case .exquisiteCorpseDrawLegs:
        keep(figure: 3, partIndex: 1, isStrip: true)
      case .exquisiteCorpseReveal:
        for index in 0..<ExquisiteCorpsePartKind.allCases.count {
          keep(figure: 2, partIndex: index, isStrip: false)
        }
      case .exquisiteCorpseRevealLoading:
        // Alex's own body is on the phone. Robin's head and legs never finish downloading.
        keep(figure: 2, partIndex: ExquisiteCorpsePartKind.body.rawValue, isStrip: false)
      default:
        break
      }
    }

    // MARK: Robin's phone

    /// The relay room, with Robin already in it when the scenario calls for it.
    /// No relay is involved: Robin's messages are fed in by the connection.
    private static func makeLive(
      for scenario: DeveloperScenario,
      coupleID: UUID,
      cache: any ExquisiteCorpseCaching
    ) -> WidgetLiveDrawing? {
      typealias Fixture = ExquisiteCorpseDeveloperFixture
      let role: WidgetLivePresence.Role?
      var plan: ExquisiteCorpseDeveloperConnection.Plan?
      switch scenario {
      case .exquisiteCorpseDrawHead, .exquisiteCorpseDrawBody, .exquisiteCorpseDrawLegs:
        // Robin has the game open and waits for Alex's part.
        role = .watching
      case .exquisiteCorpseWatching, .exquisiteCorpseHandoff:
        role = .drawing
        // At the hand-off the server has Robin's body and the turn moves to Alex.
        let handOff: @MainActor @Sendable () async -> Void = {
          try? await Task.sleep(for: .seconds(1.2))
          await cache.saveState(Fixture.legsTurn(), ownerUserID: Fixture.me)
          LocalStoreChanges.post(.games, ownerUserID: Fixture.me)
        }
        plan = ExquisiteCorpseDeveloperConnection.Plan(
          partID: Fixture.partID(figure: 3, partIndex: ExquisiteCorpsePartKind.body.rawValue),
          drawing: ExquisiteCorpsePreviewDrawings.body,
          onDone: scenario == .exquisiteCorpseHandoff ? handOff : nil
        )
      default:
        role = nil
      }
      let connection = ExquisiteCorpseDeveloperConnection(coupleID: coupleID, role: role, plan: plan)
      return WidgetLiveDrawing(
        connection: connection,
        role: .present,
        presence: WidgetLivePresence(countsLatestHelloOnly: true)
      )
    }
  }

  // MARK: - Stand-ins

  // The protocols are async, and these stand-ins answer at once.
  // swiftlint:disable async_without_await

  /// Every call succeeds and changes nothing, except the history, which answers
  /// from the fixture. The screens already show a part the moment it is saved in
  /// the pending operations.
  struct ExquisiteCorpseDeveloperGateway: ExquisiteCorpseGateway {
    /// "Our creatures" answers with no creatures.
    var historyIsEmpty = false

    func ensureExquisiteCorpseGame() async throws -> RemoteExquisiteCorpseEnsureResult {
      RemoteExquisiteCorpseEnsureResult(gameID: ExquisiteCorpseDeveloperFixture.gameID, created: false)
    }

    func loadExquisiteCorpse() async throws -> RemoteExquisiteCorpseState {
      // The cache is the scenario's state. Failing keeps the cache as it is.
      throw URLError(.notConnectedToInternet)
    }

    func submitExquisiteCorpsePart(
      _ payload: ExquisiteCorpseSubmitPartPayload,
      drawingAssetID _: UUID,
      stripAssetID _: UUID?,
      operation _: SyncClientOperation
    ) async throws -> RemoteExquisiteCorpseSubmitPartResult {
      RemoteExquisiteCorpseSubmitPartResult(
        figureID: payload.figureID,
        partID: payload.partID,
        partIndex: payload.partIndex,
        figureFinished: payload.partIndex == ExquisiteCorpsePartKind.legs.rawValue,
        createdAt: ExquisiteCorpseDeveloperFixture.now
      )
    }

    func markExquisiteCorpseRevealSeen(figureID: UUID) async throws -> RemoteExquisiteCorpseRevealSeenResult {
      RemoteExquisiteCorpseRevealSeenResult(figureID: figureID, revealSeenAt: ExquisiteCorpseDeveloperFixture.now)
    }

    func setExquisiteCorpseStar(figureID: UUID, starred: Bool) async throws -> RemoteExquisiteCorpseStarResult {
      RemoteExquisiteCorpseStarResult(figureID: figureID, starred: starred)
    }

    func loadExquisiteCorpseHistory(
      starredOnly: Bool,
      beforeFigureNumber: Int?,
      limit: Int
    ) async throws -> RemoteExquisiteCorpseHistoryPage {
      guard !historyIsEmpty else { return RemoteExquisiteCorpseHistoryPage(figures: [], nextBeforeFigureNumber: nil) }
      return ExquisiteCorpseDeveloperFixture.historyPage(
        starredOnly: starredOnly,
        before: beforeFigureNumber,
        limit: limit
      )
    }
  }

  /// The fixture drawing for every download. A stalled download waits until the
  /// screen goes away.
  struct ExquisiteCorpseDeveloperDrawingTransfer: GameDrawingTransferring {
    struct Missing: Error {}

    var stallsDownloads = false

    func uploadDrawing(
      _: Data,
      parent _: GameUploadParent,
      coupleID _: UUID,
      reserveOperation _: SyncClientOperation,
      finalizeOperation _: SyncClientOperation
    ) async throws -> UUID {
      DeveloperGamesFixture.assetID
    }

    func downloadDrawing(mediaAssetID: UUID) async throws -> Data {
      if stallsDownloads {
        try await Task.sleep(for: .seconds(86_400))
      }
      let data = await MainActor.run {
        ExquisiteCorpseDeveloperFixture.drawing(forAsset: mediaAssetID)?.dataRepresentation()
      }
      guard let data else { throw Missing() }
      return data
    }
  }

  // swiftlint:enable async_without_await

  /// A relay connection with no socket. When the room starts it, Robin joins with
  /// a role. With a plan, Robin also draws their part: the pen moves in coarse
  /// steps, and each stroke that reaches the strip is sent when it is finished,
  /// the way the real phone sends them. Without `onDone`, Robin starts over.
  @MainActor
  final class ExquisiteCorpseDeveloperConnection: WidgetLiveConnection {
    struct Plan {
      let partID: UUID
      /// What Robin draws, in the part's own coordinates.
      let drawing: PKDrawing
      /// Runs after Robin taps Done. Nil means Robin never finishes.
      var onDone: (@MainActor @Sendable () async -> Void)?
    }

    private let role: WidgetLivePresence.Role?
    private let plan: Plan?
    private var task: Task<Void, Never>?

    init(coupleID: UUID, role: WidgetLivePresence.Role?, plan: Plan?) {
      self.role = role
      self.plan = plan
      super.init(coupleID: coupleID, ticketProvider: { _ in nil })
    }

    override func start() {
      guard task == nil, let role else { return }
      task = Task { [weak self] in await self?.run(as: role) }
    }

    override func stop() {
      task?.cancel()
      task = nil
    }

    override func send(_: WidgetLiveMessage) {}

    override func send(gameData _: Data) {}

    private func run(as role: WidgetLivePresence.Role) async {
      onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
      onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role.rawValue))
      guard let plan else { return }
      // The screen settles before Robin starts.
      try? await Task.sleep(for: .seconds(1))
      while !Task.isCancelled {
        await draw(plan)
        guard !Task.isCancelled else { return }
        if let onDone = plan.onDone {
          deliver(.done(partID: plan.partID))
          await onDone()
          return
        }
        try? await Task.sleep(for: .seconds(3))
        // Robin starts the part again, so the strip empties.
        deliver(.strip(partID: plan.partID, drawing: PKDrawing().dataRepresentation().base64EncodedString()))
      }
    }

    /// One pass over the drawing: the pen along each stroke, then the strip.
    private func draw(_ plan: Plan) async {
      let side = GameCanvas.canonicalSide
      var sampler = ExquisiteCorpsePenSampler()
      var strip = PKDrawing()
      var time: TimeInterval = 0
      for stroke in plan.drawing.strokes {
        let last = CGFloat(stroke.path.count - 1)
        let steps = max(3, min(12, Int(last * 3)))
        for step in 0...steps {
          let point = stroke.path
            .interpolatedLocation(at: last * CGFloat(step) / CGFloat(steps))
            .applying(stroke.transform)
          time += Self.penInterval
          if let sample = sampler.move(x: Double(point.x / side), y: Double(point.y / side), at: time) {
            deliver(.pen(partID: plan.partID, x: sample.x, y: sample.y))
          }
          try? await Task.sleep(for: .seconds(Self.penInterval))
          guard !Task.isCancelled else { return }
        }
        let lift = sampler.lift()
        deliver(.pen(partID: plan.partID, x: lift.x, y: lift.y))
        let piece = ExquisiteCorpseFold.strip(of: PKDrawing(strokes: [stroke]))
        if !piece.strokes.isEmpty {
          strip.append(piece)
          deliver(.strip(partID: plan.partID, drawing: strip.dataRepresentation().base64EncodedString()))
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
      }
    }

    /// The real phone sends at most 8 positions a second.
    private static let penInterval: TimeInterval = 1.0 / 8

    private func deliver(_ message: ExquisiteCorpseLiveMessage) {
      guard let data = try? JSONEncoder().encode(
        GameLiveEnvelope(game: ExquisiteCorpseLiveMessage.game, message: message)
      ) else { return }
      onGameData?(data)
    }
  }

  // MARK: - Screen

  /// An Exquisite corpse screen on its own, in a stack that opens "Our creatures"
  /// and a creature. The routes are the production ones (`GamesViewModel.screen(for:)`).
  @MainActor
  struct ExquisiteCorpseDeveloperScenarioView: View {
    let scenario: DeveloperScenario
    @State private var viewModel: GamesViewModel
    @State private var path: [GamesDestination] = []
    @State private var isReady = false

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      let viewModel = DeveloperGamesScenarioFactory.gamesViewModel(for: scenario)
      viewModel.configure(participants: DeveloperGamesFixture.participants)
      _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
      NavigationStack(path: $path) {
        Group {
          if isReady, let screen = viewModel.screen(for: root) {
            screen
          } else {
            Color.paeoniaBackgroundPrimary
          }
        }
        .navigationDestination(for: GamesDestination.self) { destination in
          viewModel.screen(for: destination)
        }
      }
      .task {
        await seed()
        isReady = true
        await openCreatureIfNeeded()
      }
    }

    /// The history scenarios start at "Our creatures". The others start in the game.
    private var root: GamesDestination {
      switch scenario {
      case .exquisiteCorpseHistory, .exquisiteCorpseHistoryEmpty, .exquisiteCorpseHistoryStarred,
        .exquisiteCorpseHistoryDetail:
        .exquisiteCorpseHistory
      default:
        .game(.exquisiteCorpse)
      }
    }

    /// Puts the scenario's saved moves in place before the screen reads them.
    private func seed() async {
      let game = viewModel.exquisiteCorpse.game
      switch scenario {
      case .exquisiteCorpseDrawLegs:
        // The idea chip a relaunch brings back.
        let partID = ExquisiteCorpseDeveloperFixture.partID(figure: 3, partIndex: ExquisiteCorpsePartKind.legs.rawValue)
        await game.dependencies.exquisiteCorpseCache.saveIdea(
          ExquisiteCorpseDeveloperFixture.ideas[1].id,
          partID: partID,
          ownerUserID: ExquisiteCorpseDeveloperFixture.me
        )
      case .exquisiteCorpseWaitingToSync:
        await queueLegs(on: game)
      case .exquisiteCorpseHistoryStarred:
        viewModel.exquisiteCorpse.history.filter = .starred
      default:
        break
      }
    }

    /// Alex's legs, saved on the phone after a try that did not get through.
    private func queueLegs(on game: ExquisiteCorpseViewModel) async {
      let payload = ExquisiteCorpseDeveloperFixture.queuedLegs()
      guard let data = try? JSONEncoder().encode(payload) else { return }
      let store = game.dependencies.pendingOperationStore
      let operation = SyncClientOperation(
        clientID: UUID(),
        clientSequence: 100,
        localCreatedAt: ExquisiteCorpseDeveloperFixture.now
      )
      try? await store.enqueue(
        PendingSyncOperationRequest(
          ownerUserID: ExquisiteCorpseDeveloperFixture.me,
          operation: operation,
          operationKind: .exquisiteCorpseSubmitPart,
          idempotencyScope: "exquisite-corpse-part:\(payload.partID.uuidString.lowercased())",
          requestData: data
        )
      )
      // The phone is offline, so the screen says the part is saved on it.
      try? await store.markRetryableFailure(
        clientOperationID: operation.id,
        errorDescription: "NSURLErrorDomain",
        nextRetryAt: nil,
        at: ExquisiteCorpseDeveloperFixture.now
      )
    }

    /// The creature scenario loads the list first, because a creature opens from it.
    private func openCreatureIfNeeded() async {
      guard scenario == .exquisiteCorpseHistoryDetail else { return }
      let history = viewModel.exquisiteCorpse.history
      await history.refresh()
      path = [.exquisiteCorpseHistoryDetail(ExquisiteCorpseDeveloperFixture.figureID(11))]
    }
  }
#endif
