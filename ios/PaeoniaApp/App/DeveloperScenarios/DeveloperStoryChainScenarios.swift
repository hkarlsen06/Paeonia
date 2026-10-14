#if DEBUG
  import Foundation
  import SwiftUI

  /// Story Chain scenarios. They run the real screen, view model and hub model on
  /// in-memory dependencies, so every phase can be reached without a partner, a
  /// network, or the Convex backend.
  ///
  /// The cache holds a fixed server state, and the pending operations are in
  /// memory. A move made here (picking an opening, a line, a title) changes the
  /// screen the way it does on an offline phone.
  /// The state factory is plain data and the gateway reads it off the main
  /// actor. The live room helpers stay on the main actor.
  nonisolated enum DeveloperStoryChainScenarios {
    typealias Fixture = DeveloperStoryChainFixture

    /// A scenario's fixed server state. Scenarios that are not about Story Chain
    /// get story 4 with Alex's turn to write, so the hub shows the game's card.
    static func state(for scenario: DeveloperScenario) -> RemoteStoryChainState {
      switch scenario {
      case .storyChainChoose, .storyChainChooseOffline, .storyChainWaitingOpening:
        betweenStories(for: scenario)
      case .storyChainWritingLast:
        Fixture.lastLine()
      case .storyChainWaitingLive, .storyChainWaitingAway:
        Fixture.writing(lines: 7)
      case .storyChainNaming:
        Fixture.titling(namedBy: Fixture.me)
      case .storyChainWaitingName:
        Fixture.titling(namedBy: Fixture.partner)
      case .storyChainFinished:
        Fixture.finished()
      default:
        Fixture.writing(lines: 8)
      }
    }

    /// The last story is finished and seen, and the next one is not started.
    private static func betweenStories(for scenario: DeveloperScenario) -> RemoteStoryChainState {
      switch scenario {
      case .storyChainWaitingOpening:
        Fixture.choosing(turn: Fixture.partner, openings: nil)
      case .storyChainChooseOffline:
        Fixture.choosing(turn: Fixture.me, openings: nil)
      default:
        Fixture.choosing(turn: Fixture.me, openings: Fixture.openings)
      }
    }

    /// The live room, with the partner already in it when the scenario calls for
    /// it. No relay is involved: the partner's messages are fed in directly.
    @MainActor
    static func makeLive(
      for scenario: DeveloperScenario,
      coupleID: UUID,
      cache: InMemoryStoryChainCache
    ) -> WidgetLiveDrawing {
      let connection = WidgetLiveConnection(coupleID: coupleID, ticketProvider: { _ in nil })
      let live = WidgetLiveDrawing(
        connection: connection,
        role: .present,
        presence: WidgetLivePresence(countsLatestHelloOnly: true)
      )
      switch scenario {
      case .storyChainWriting:
        simulatePartner(on: connection, role: .watching)
      case .storyChainWaitingName, .storyChainWaitingOpening:
        simulatePartner(on: connection, role: .choosing)
      case .storyChainWaitingLive:
        simulatePartner(on: connection, role: .drawing)
        let typist = DeveloperStoryChainPartnerTypist(connection: connection, cache: cache)
        Task { await typist.run() }
      default:
        break
      }
      return live
    }

    /// The partner opens the game with `role`, which is what their screen shows.
    @MainActor
    fileprivate static func simulatePartner(on connection: WidgetLiveConnection, role: WidgetLivePresence.Role) {
      connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
      connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role.rawValue))
    }
  }

  /// Robin writes line 8 in front of the reader: letters one at a time, a slip
  /// that gets deleted, a phrase that gets dropped, a pause, then Send. A second
  /// later the server confirms the line and the turn is Alex's. It runs once. The
  /// reset button plays it again.
  @MainActor
  private final class DeveloperStoryChainPartnerTypist {
    private enum Keystroke {
      case type(String)
      case delete(Int)
      case pause(Double)
    }

    private typealias Fixture = DeveloperStoryChainFixture

    private weak var connection: WidgetLiveConnection?
    private let cache: InMemoryStoryChainCache
    private var draft = ""
    private let number = 8
    private let storyID = Fixture.storyID(Fixture.storyNumber)
    private let lineID = Fixture.lineID(story: Fixture.storyNumber, number: 8)

    init(connection: WidgetLiveConnection, cache: InMemoryStoryChainCache) {
      self.connection = connection
      self.cache = cache
    }

    func run() async {
      // The screen is open and the reader looks at the page.
      guard await pause(2.5) else { return }
      let text = Fixture.partnerLiveLine.text
      for step in Self.keystrokes(for: text) {
        guard await perform(step) else { return }
      }
      guard await pause(0.8) else { return }
      send(text, sent: true)
      guard await pause(1.5), let connection else { return }
      // Convex confirms the line with the same id, and the turn is Alex's.
      await cache.saveState(Fixture.writing(lines: number, version: 2), ownerUserID: Fixture.me)
      LocalStoreChanges.post(.games, ownerUserID: Fixture.me)
      DeveloperStoryChainScenarios.simulatePartner(on: connection, role: .watching)
    }

    /// The text with a stray key after the first words and a dropped phrase after
    /// the next ones. Both are deleted again, so it ends as `text`.
    private static func keystrokes(for text: String) -> [Keystroke] {
      let characters = Array(text)
      guard characters.count > 40 else { return [.type(text)] }
      func wordEnd(after fraction: Double) -> Int {
        let start = Int(Double(characters.count) * fraction)
        return characters[start...].firstIndex(of: " ") ?? characters.count
      }
      let slip = wordEnd(after: 0.3)
      let dropped = wordEnd(after: 0.7)
      let abandoned = " well, actually"
      return [
        .type(String(characters[..<slip])),
        .type("qw"), .pause(0.4), .delete(2),
        .type(String(characters[slip..<dropped])),
        .type(abandoned), .pause(0.9), .delete(abandoned.count), .pause(0.4),
        .type(String(characters[dropped...])),
      ]
    }

    private func perform(_ step: Keystroke) async -> Bool {
      switch step {
      case let .type(text):
        for character in text {
          draft.append(character)
          send(draft)
          guard await pause(0.045 + Double(draft.count % 5) * 0.012) else { return false }
        }
        return true
      case let .delete(count):
        for _ in 0..<count where !draft.isEmpty {
          draft.removeLast()
          send(draft)
          guard await pause(0.06) else { return false }
        }
        return true
      case let .pause(seconds):
        return await pause(seconds)
      }
    }

    /// Waits. False when the screen is gone, so the typing stops.
    private func pause(_ seconds: Double) async -> Bool {
      guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return false }
      return connection != nil
    }

    /// The partner's phone sends the draft, or at Send the final line with its id.
    private func send(_ text: String, sent: Bool = false) {
      let message = StoryChainLiveMessage(
        story: storyID,
        number: number,
        text: text,
        isLast: false,
        lineID: sent ? lineID : nil,
        sent: sent
      )
      let envelope = GameLiveEnvelope(game: StoryChainLiveMessage.game, message: message)
      guard let data = try? JSONEncoder().encode(envelope) else { return }
      connection?.onGameData?(data)
    }
  }

  // MARK: - Views

  /// A Story Chain phase on its own screen, with the stack that opens "Our stories".
  @MainActor
  struct DeveloperStoryChainScenarioView: View {
    let scenario: DeveloperScenario
    @State private var hub: StoryChainHubModel
    @State private var isReady = false

    init(scenario: DeveloperScenario) {
      self.scenario = scenario
      _hub = State(initialValue: DeveloperStoryChainHub.make(for: scenario))
    }

    var body: some View {
      NavigationStack {
        if isReady {
          StoryChainScreen(viewModel: hub.game)
            .navigationDestination(for: GamesDestination.self) { destination in
              if let screen = hub.screen(for: destination) {
                screen
              }
            }
        } else {
          Color.paeoniaBackgroundPrimary
        }
      }
      .task {
        await seed()
        isReady = true
      }
    }

    /// Puts the scenario's unsent line in the queue before the screen reads it.
    /// The line went through the normal queue and its first try failed for lack of
    /// a connection, so the page says "Saved on this phone".
    private func seed() async {
      guard scenario == .storyChainSavedOffline else { return }
      typealias Fixture = DeveloperStoryChainFixture
      let line = StoryChainQueuedLine(
        storyID: Fixture.storyID(Fixture.storyNumber),
        lineID: Fixture.lineID(story: Fixture.storyNumber, number: 9),
        text: Fixture.lighthouse[8].text,
        isLast: false,
        createdAt: Fixture.now
      )
      let store = hub.game.dependencies.pendingOperationStore
      try? await hub.game.moveQueue.addLine(line, ownerUserID: Fixture.me)
      let queued = try? await store.inFlightOperations(ownerUserID: Fixture.me, kind: .storyChainAddLine)
      guard let operationID = queued?.first?.operation.id else { return }
      try? await store.markSending(clientOperationID: operationID, at: Fixture.now)
      try? await store.markRetryableFailure(
        clientOperationID: operationID,
        errorDescription: "NSURLErrorDomain Code=-1009",
        nextRetryAt: Fixture.now.addingTimeInterval(60),
        at: Fixture.now
      )
    }
  }

  /// "Our stories" on its own screen, with a stack that opens a story.
  @MainActor
  struct DeveloperStoryChainHistoryScenarioView: View {
    @State private var hub: StoryChainHubModel

    init(scenario: DeveloperScenario) {
      _hub = State(initialValue: DeveloperStoryChainHub.make(for: scenario))
    }

    var body: some View {
      NavigationStack {
        StoryChainHistoryScreen(viewModel: hub.history)
          .navigationDestination(for: GamesDestination.self) { destination in
            if let screen = hub.screen(for: destination) {
              screen
            }
          }
      }
    }
  }

  /// The hub model both scenario views use, built the way the Games tab builds it,
  /// so the screens, the stars and the routes are the production ones.
  @MainActor
  private enum DeveloperStoryChainHub {
    static func make(for scenario: DeveloperScenario) -> StoryChainHubModel {
      let dependencies = DeveloperGamesScenarioFactory.dependencies(for: scenario)
      let game = StoryChainViewModel(dependencies: dependencies, participants: DeveloperGamesFixture.participants)
      let hub = StoryChainHubModel(dependencies: dependencies, game: game)
      hub.configure(participants: DeveloperGamesFixture.participants)
      return hub
    }
  }
#endif
