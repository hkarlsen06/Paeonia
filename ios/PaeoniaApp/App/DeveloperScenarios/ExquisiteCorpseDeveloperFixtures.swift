#if DEBUG
  import Foundation
  import PencilKit

  /// Deterministic Exquisite corpse states for the scenarios. Alex is the
  /// signed-in person and Robin is the partner. Alex starts the odd creatures and
  /// Robin the even ones, so Alex drew the first head. Every date counts from
  /// `DeveloperScenarioFixture.now`.
  ///
  /// Every file is one of the preview drawings: a cat's head, a striped sweater
  /// and chicken legs. `drawing(forAsset:)` finds the drawing for an asset id.
  enum ExquisiteCorpseDeveloperFixture {
    nonisolated static let gameID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000c1") ?? UUID()
    nonisolated static let me = DeveloperGamesFixture.me
    nonisolated static let partner = DeveloperGamesFixture.partner
    nonisolated static let now = DeveloperGamesFixture.now

    // MARK: Who draws what

    nonisolated static func starter(ofFigure number: Int) -> UUID {
      number.isMultiple(of: 2) ? partner : me
    }

    /// The starter draws the head and the legs. The other person draws the body.
    nonisolated static func drawer(ofFigure number: Int, partIndex: Int) -> UUID {
      let starter = starter(ofFigure: number)
      guard partIndex == ExquisiteCorpsePartKind.body.rawValue else { return starter }
      return starter == me ? partner : me
    }

    nonisolated static func figureID(_ number: Int) -> UUID {
      ExquisiteCorpseIDs.figure(gameID: gameID, number: number)
    }

    nonisolated static func partID(figure number: Int, partIndex: Int) -> UUID {
      ExquisiteCorpseIDs.part(
        gameID: gameID,
        figureNumber: number,
        partIndex: partIndex,
        drawerID: drawer(ofFigure: number, partIndex: partIndex)
      )
    }

    // MARK: Files

    /// The file of a part, or its strip. The last two hex digits say which part
    /// and whether it is the strip, so the transfer can answer without a table.
    nonisolated static func assetID(figure number: Int, partIndex: Int, isStrip: Bool) -> UUID {
      let code = partIndex * 2 + (isStrip ? 1 : 0)
      return UUID(uuidString: String(format: "cccc0000-%04x-4000-8000-0000000000%02x", number, code)) ?? UUID()
    }

    /// The drawing behind an asset id of `assetID(figure:partIndex:isStrip:)`.
    @MainActor
    static func drawing(forAsset assetID: UUID) -> PKDrawing? {
      guard assetID.uuidString.lowercased().hasPrefix("cccc0000-"),
            let code = Int(assetID.uuidString.suffix(2), radix: 16),
            let kind = ExquisiteCorpsePartKind(rawValue: code / 2)
      else { return nil }
      let part = previewDrawing(kind)
      return code.isMultiple(of: 2) ? part : ExquisiteCorpseFold.strip(of: part)
    }

    @MainActor
    static func previewDrawing(_ kind: ExquisiteCorpsePartKind) -> PKDrawing {
      switch kind {
      case .head: ExquisiteCorpsePreviewDrawings.head
      case .body: ExquisiteCorpsePreviewDrawings.body
      case .legs: ExquisiteCorpsePreviewDrawings.legs
      }
    }

    // MARK: Pieces

    nonisolated static let ideas = [
      "a grandma", "a robot", "a very tired knight", "a cloud with opinions", "a fox in a raincoat", "a teapot",
    ].map { RemoteExquisiteCorpseIdea(id: "idea-\($0.replacingOccurrences(of: " ", with: "-"))", text: $0) }

    /// A part as this person may read it: their own, or any part of a finished creature.
    nonisolated static func part(
      figure number: Int,
      partIndex: Int,
      idea: String? = nil,
      isFinished: Bool
    ) -> RemoteExquisiteCorpsePart {
      let drawer = drawer(ofFigure: number, partIndex: partIndex)
      let isReadable = isFinished || drawer == me
      return RemoteExquisiteCorpsePart(
        id: partID(figure: number, partIndex: partIndex),
        partIndex: partIndex,
        drawerUserID: drawer,
        createdAt: now.addingTimeInterval(-Double(3 - partIndex) * 3_600 - Double(number) * 86_400),
        stripMediaAssetID: partIndex < ExquisiteCorpsePartKind.legs.rawValue
          ? assetID(figure: number, partIndex: partIndex, isStrip: true) : nil,
        drawingMediaAssetID: isReadable ? assetID(figure: number, partIndex: partIndex, isStrip: false) : nil,
        idea: isReadable ? idea.map { RemoteExquisiteCorpseIdea(id: "idea-\($0)", text: $0) } : nil
      )
    }

    /// A figure with its first `parts` parts. A finished figure has all three.
    nonisolated static func figure(
      _ number: Int,
      parts count: Int = 3,
      ideas: [String?] = [],
      isRevealSeen: Bool = true
    ) -> RemoteExquisiteCorpseFigure {
      let isFinished = count == ExquisiteCorpsePartKind.allCases.count
      let finishedAt = now.addingTimeInterval(-Double(number) * 86_400)
      return RemoteExquisiteCorpseFigure(
        id: figureID(number),
        number: number,
        starterUserID: starter(ofFigure: number),
        createdAt: finishedAt.addingTimeInterval(-7_200),
        finishedAt: isFinished ? finishedAt : nil,
        myRevealSeenAt: isFinished && isRevealSeen ? finishedAt.addingTimeInterval(600) : nil,
        parts: (0..<count).map { index in
          let idea = ideas.indices.contains(index) ? ideas[index] : nil
          return part(figure: number, partIndex: index, idea: idea, isFinished: isFinished)
        }
      )
    }

    nonisolated static func game(
      figure number: Int,
      partIndex: Int,
      turn: UUID,
      figuresFinished: Int,
      version: Int = 5
    ) -> RemoteExquisiteCorpseGame {
      RemoteExquisiteCorpseGame(
        id: gameID,
        turnUserID: turn,
        turnStartedAt: now.addingTimeInterval(-600),
        figureID: partIndex == 0 ? nil : figureID(number),
        figureNumber: number,
        partIndex: partIndex,
        figuresFinished: figuresFinished,
        version: version,
        createdAt: now.addingTimeInterval(-86_400 * 14),
        updatedAt: now.addingTimeInterval(-600)
      )
    }

    nonisolated static func state(
      game: RemoteExquisiteCorpseGame?,
      current: RemoteExquisiteCorpseFigure? = nil,
      recent: [RemoteExquisiteCorpseFigure] = [],
      ideas: [RemoteExquisiteCorpseIdea] = []
    ) -> RemoteExquisiteCorpseState {
      RemoteExquisiteCorpseState(
        userID: me,
        partnerUserID: partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        dataEpoch: "",
        game: game,
        currentFigure: current,
        recentFigures: recent,
        ideas: ideas
      )
    }

    // MARK: States

    /// Creature 1 is new and Alex draws its head.
    nonisolated static func headTurn() -> RemoteExquisiteCorpseState {
      state(game: game(figure: 1, partIndex: 0, turn: me, figuresFinished: 0), ideas: ideas)
    }

    /// Robin drew the head of creature 2, and Alex draws the body.
    nonisolated static func bodyTurn(figuresFinished: Int = 1, version: Int = 5) -> RemoteExquisiteCorpseState {
      state(
        game: game(figure: 2, partIndex: 1, turn: me, figuresFinished: figuresFinished, version: version),
        current: figure(2, parts: 1),
        recent: figuresFinished > 0 ? [figure(1, ideas: ["a cat", nil, "chicken legs"])] : [],
        ideas: ideas
      )
    }

    /// Alex drew the head of creature 3 and Robin the body. Alex draws the legs.
    nonisolated static func legsTurn(version: Int = 6) -> RemoteExquisiteCorpseState {
      state(
        game: game(figure: 3, partIndex: 2, turn: me, figuresFinished: 2, version: version),
        current: figure(3, parts: 2),
        recent: [figure(2)],
        ideas: ideas
      )
    }

    /// Alex drew the head of creature 3, and Robin draws the body.
    nonisolated static func partnerBodyTurn(figuresFinished: Int = 2) -> RemoteExquisiteCorpseState {
      state(
        game: game(figure: 3, partIndex: 1, turn: partner, figuresFinished: figuresFinished),
        current: figure(3, parts: 1),
        recent: [figure(2)]
      )
    }

    /// Robin starts creature 4 and has drawn the head. Alex drew the body. Robin draws the legs.
    nonisolated static func partnerLegsTurn(figuresFinished: Int = 12) -> RemoteExquisiteCorpseState {
      state(
        game: game(figure: 4, partIndex: 2, turn: partner, figuresFinished: figuresFinished),
        current: figure(4, parts: 2),
        recent: [figure(3)]
      )
    }

    /// Creature 2 is finished and Alex has not seen it. Alex drew its body, so
    /// Alex starts creature 3.
    nonisolated static func unseenReveal(figuresFinished: Int = 2) -> RemoteExquisiteCorpseState {
      state(
        game: game(figure: 3, partIndex: 0, turn: me, figuresFinished: figuresFinished),
        recent: [figure(2, ideas: ["a cat", nil, "chicken legs"], isRevealSeen: false), figure(1)]
      )
    }

    /// The game does not exist yet.
    nonisolated static func notStarted() -> RemoteExquisiteCorpseState {
      state(game: nil)
    }

    // MARK: History

    nonisolated private static let historyIdeas: [[String?]] = [
      ["a cat", nil, "chicken legs"], [nil, "a sweater", nil], ["a robot", "a teapot", nil],
    ]

    /// Newest first, creature 12 down to creature 1.
    nonisolated static func historyFigures() -> [RemoteExquisiteCorpseFigure] {
      (1...12).reversed().map { number in
        figure(number, ideas: historyIdeas[number % historyIdeas.count])
      }
    }

    /// The creatures this person has starred: 12, 9, 6 and 3.
    nonisolated static let historyStarredFigureIDs: Set<UUID> = Set([12, 9, 6, 3].map(figureID))

    /// The favorites of the "Our creatures" scenarios: the starred creatures.
    @MainActor
    static func favoritesStore() -> FavoritesStore {
      FavoritesStore.preloaded(
        ownerUserID: me,
        favorites: historyStarredFigureIDs.map { FavoriteRef(target: .corpseFigure($0), createdAt: now) }
      )
    }

    /// The server's answer for a page: creatures before the cursor, optionally
    /// only the starred ones. The tests use it too.
    nonisolated static func historyPage(
      from figures: [RemoteExquisiteCorpseFigure] = historyFigures(),
      starred: Set<UUID> = historyStarredFigureIDs,
      starredOnly: Bool,
      before: Int?,
      limit: Int
    ) -> RemoteExquisiteCorpseHistoryPage {
      let matching = figures.filter { figure in
        (before.map { figure.number < $0 } ?? true) && (!starredOnly || starred.contains(figure.id))
      }
      let page = Array(matching.prefix(limit))
      return RemoteExquisiteCorpseHistoryPage(
        figures: page,
        nextBeforeFigureNumber: matching.count > limit ? page.last?.number : nil
      )
    }

    // MARK: Overview

    /// The shared overview: the couple's settings, and Robin's heartbeat for this game.
    static func overview(partnerIsHere: Bool) -> RemoteGamesOverview {
      RemoteGamesOverview(
        userID: me,
        partnerUserID: partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        settings: DeveloperGamesFixture.settings(),
        presence: partnerIsHere ? [
          RemoteGamePresence(
            kind: .exquisiteCorpse,
            myPresent: false,
            partnerPresent: true,
            lastInviteAt: nil
          ),
        ] : []
      )
    }

    // MARK: Queued legs

    /// Alex's legs for creature 3, saved on the phone and not sent. They match the
    /// next part the server waits for in `legsTurn()`.
    @MainActor
    static func queuedLegs() -> ExquisiteCorpseSubmitPartPayload {
      func upload(_ data: Data, sequence: Int64) -> ExquisiteCorpseQueuedUpload {
        ExquisiteCorpseQueuedUpload(
          data: data,
          reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: sequence),
          finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: sequence + 1)
        )
      }
      return ExquisiteCorpseSubmitPartPayload(
        gameID: gameID,
        figureID: figureID(3),
        partID: partID(figure: 3, partIndex: ExquisiteCorpsePartKind.legs.rawValue),
        partIndex: ExquisiteCorpsePartKind.legs.rawValue,
        coupleID: DeveloperScenarioFixture.coupleID,
        drawing: upload(ExquisiteCorpsePreviewDrawings.legs.dataRepresentation(), sequence: 101),
        strip: nil,
        idea: nil,
        createdAt: now.addingTimeInterval(-120)
      )
    }
  }
#endif
