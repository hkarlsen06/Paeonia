#if DEBUG
  import SwiftUI

  /// The partner's avatar over the real paired app, for screenshots and the presence journey. Each
  /// scenario brings a partner who stays where the scenario puts them.
  nonisolated extension DeveloperScenario {
    static let presence: [DeveloperScenario] = [
      presenceUsTab, presencePlaying, presenceMessage, presenceTyping, presenceTucked, presenceOverCover,
      presenceInChat, presenceLetter, presenceUnread, presenceOpenedGame, presenceOpenedDrawing,
      localFlowPresence, localFlowPresenceGameChat,
    ]

    static let presenceUsTab = DeveloperScenario(
      "presence-us-tab", "Presence · Robin is here", "Robin's picture over Us while you both have the app open",
      .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence()) }

    static let presencePlaying = DeveloperScenario(
      "presence-playing", "Presence · Robin plays Mind Meld",
      "Robin is in Mind Meld, and the toolbar is open with Call, Message and Join", .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(games: [.mindMeld]), mode: .expanded(pending: nil)) }

    static let presenceMessage = DeveloperScenario(
      "presence-message", "Presence · Robin's message",
      "Robin writes in Just us, and the message shows beside the picture instead of a banner", .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(chat: .couple), notice: DeveloperPresenceFixture.message) }

    static let presenceTyping = DeveloperScenario(
      "presence-typing", "Presence · Robin types", "Robin types in Just us", .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(chat: .couple, typing: .couple)) }

    static let presenceTucked = DeveloperScenario(
      "presence-tucked", "Presence · tucked away",
      "The picture thrown past the right edge, with a dot for Robin's message that came meanwhile", .presence
    ) { _ in
      DeveloperPresenceFlow(
        partner: PartnerPresence(chat: .couple), mode: .tucked(edge: .trailing, pending: nil),
        notice: DeveloperPresenceFixture.message)
    }

    static let presenceOverCover = DeveloperScenario(
      "presence-over-cover", "Presence · over the answer flow",
      "Today's question is open, so Robin's picture waits as a tab at the edge, with a dot for Robin's message",
      .presence
    ) { _ in
      DeveloperPresenceFlow(
        partner: PartnerPresence(chat: .couple), notice: DeveloperPresenceFixture.message,
        launchLink: "paeonia://daily/today")
    }

    static let presenceInChat = DeveloperScenario(
      "presence-in-chat", "Presence · in Just us", "Just us is open, and Robin's picture keeps clear of the composer",
      .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(chat: .couple), launchLink: "paeonia://chat") }

    static let presenceLetter = DeveloperScenario(
      "presence-letter", "Presence · Robin's letter",
      "Robin sends a letter while you both have the app open, and the picture says so instead of a banner",
      .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(), pushNotice: DeveloperPresenceFixture.letterPush) }

    static let presenceUnread = DeveloperScenario(
      "presence-unread", "Presence · Robin writes in Mind Meld",
      "Robin's message grows out of the picture, goes back in after a few seconds, and leaves a count", .presence
    ) { _ in
      DeveloperPresenceFlow(
        partner: PartnerPresence(games: [.mindMeld]), noticeDuration: .seconds(4), partnerWrites: true)
    }

    static let presenceOpenedGame = DeveloperScenario(
      "presence-opened-game", "Presence · Robin opens Mind Meld",
      "Robin opens Mind Meld, and the picture opens with Call, Message and Join for a few seconds", .presence
    ) { _ in
      DeveloperPresenceFlow(partner: PartnerPresence(games: [.mindMeld]), notice: .openedGame(.mindMeld))
    }

    static let presenceOpenedDrawing = DeveloperScenario(
      "presence-opened-drawing", "Presence · Robin opens the drawing",
      "Robin opens your drawing, and the picture opens with Call, Message and Join for a few seconds", .presence
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(isDrawing: true), notice: .openedDrawing) }

    static let localFlowPresence = DeveloperScenario(
      "local-flow-presence", "Local flow · Robin in Mind Meld",
      "Tap Robin's picture over Us, write in Just us from Message, and join Robin's game", .localFlows
    ) { _ in DeveloperPresenceFlow(partner: PartnerPresence(games: [.mindMeld]), noticeDuration: .seconds(5)) }

    static let localFlowPresenceGameChat = DeveloperScenario(
      "local-flow-presence-game-chat", "Local flow · Message in Four in a Row",
      "Message from Robin's picture opens the game's chat over the board, and Message again opens Just us",
      .localFlows
    ) { _ in
      DeveloperLocalFlowHost(
        seed: .paired, gameConversation: .connectFourPartnerTurn, launchLink: "paeonia://games/connect-four",
        avatarStories: .noStory,
        presence: DeveloperPresenceFixture.model(partner: PartnerPresence(games: [.connectFour])))
    }
  }

  nonisolated enum DeveloperPresenceFixture {
    static let message = PresenceNotice.message(
      PresenceMessageNotice(
        messageID: UUID(uuidString: "9e5e9ce0-0000-4000-8000-000000000001") ?? UUID(), chat: .couple,
        preview: "Are you coming home soon? I made too much pasta 🍝"))

    /// The push a letter sends, as it arrives while the app is open.
    static let letterPush = PaeoniaForegroundNotice(
      title: "Robin sent you a letter", message: "Open it in the Us tab.", deepLink: .mail(letterID: nil),
      showsPartnerAvatar: true, isPartnersDoing: true)

    /// A model whose partner is always `partner`. Screenshot scenarios keep a notice on screen for
    /// an hour.
    @MainActor
    static func model(
      partner: PartnerPresence, mode: PresencePillMode = .avatar(notice: nil),
      noticeDuration: Duration = .seconds(3_600)
    ) -> PartnerPresenceModel {
      PartnerPresenceModel(
        gateway: DeveloperPartnerPresenceGateway(feed: DeveloperPresenceFeed(partner: partner)),
        noticeDuration: noticeDuration, mode: mode)
    }
  }

  /// The paired app with the partner's avatar. `notice` arrives a moment after the app shows, as a
  /// live message does, and `pushNotice` as a push that arrives while the app is open. `launchLink`
  /// opens as the app starts. Mind Meld is on Games, so Join opens it.
  private struct DeveloperPresenceFlow: View {
    @State private var model: PartnerPresenceModel
    private let notice: PresenceNotice?
    private let pushNotice: PaeoniaForegroundNotice?
    private let launchLink: String?
    private let partnerWrites: Bool

    init(
      partner: PartnerPresence, mode: PresencePillMode = .avatar(notice: nil), notice: PresenceNotice? = nil,
      pushNotice: PaeoniaForegroundNotice? = nil, noticeDuration: Duration = .seconds(3_600),
      launchLink: String? = nil, partnerWrites: Bool = false
    ) {
      self.partnerWrites = partnerWrites
      _model = State(
        initialValue: DeveloperPresenceFixture.model(partner: partner, mode: mode, noticeDuration: noticeDuration))
      self.notice = notice
      self.pushNotice = pushNotice
      self.launchLink = launchLink
    }

    var body: some View {
      DeveloperLocalFlowHost(
        seed: .paired, gameConversation: .mindMeldWrite, launchLink: launchLink, avatarStories: .noStory,
        presence: model, partnerWritesAfter: partnerWrites ? .seconds(1.5) : nil)
        .task {
          guard notice != nil || pushNotice != nil else { return }
          // A moment after the avatar shows, as a live notice would.
          while !model.isShown, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
          try? await Task.sleep(for: .seconds(1.5))
          guard !Task.isCancelled else { return }
          if let notice { model.receive(notice) }
          if let pushNotice { PaeoniaNotificationRouter.shared.presentForegroundNotice(pushNotice) }
        }
    }
  }

  /// The partner in a scenario. "Show when I'm here" hides them and brings them back as the server
  /// would.
  @MainActor
  final class DeveloperPresenceFeed {
    private let partner: PartnerPresence
    private var showsPresence = true
    private var continuations: [UUID: AsyncStream<PartnerPresenceReading?>.Continuation] = [:]

    init(partner: PartnerPresence) {
      self.partner = partner
    }

    private var reading: PartnerPresenceReading {
      PartnerPresenceReading(showsPresence: showsPresence, partner: showsPresence ? partner : nil)
    }

    func add(_ continuation: AsyncStream<PartnerPresenceReading?>.Continuation, id: UUID) {
      continuations[id] = continuation
      continuation.yield(reading)
    }

    func remove(id: UUID) {
      continuations[id] = nil
    }

    func setShowsPresence(_ shows: Bool) {
      showsPresence = shows
      for continuation in continuations.values {
        continuation.yield(reading)
      }
    }
  }

  nonisolated struct DeveloperPartnerPresenceGateway: PartnerPresenceGateway {
    let feed: DeveloperPresenceFeed

    func setInApp(_: Bool, isDrawing _: Bool) {}

    func setShowsPresence(_ shows: Bool) async -> Bool {
      await feed.setShowsPresence(shows)
      return shows
    }

    func readings(coupleID _: UUID) -> AsyncStream<PartnerPresenceReading?> {
      AsyncStream { continuation in
        let id = UUID()
        Task { @MainActor in feed.add(continuation, id: id) }
        continuation.onTermination = { _ in Task { @MainActor in feed.remove(id: id) } }
      }
    }
  }
#endif
