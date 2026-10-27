#if DEBUG
  import Foundation
  import MapKit
  import SwiftUI

  /// Fixed Guess my spot states for the developer scenarios. The pending operations
  /// are in memory, so a move made here changes the screen the way it does on a
  /// phone that is offline.
  @MainActor
  enum DeveloperGuessMySpotScenarioFactory {
    typealias Fixture = DeveloperGamesFixture
    typealias Spot = GuessMySpotCoordinate

    nonisolated static let gameID = UUID(uuidString: "6E55E5E5-0000-4000-8000-000000000001") ?? UUID()
    nonisolated static let roundID = UUID(uuidString: "6E55E5E5-0000-4000-8000-000000000002") ?? UUID()
    nonisolated static let harborAssetID = UUID(uuidString: "6E55E5E5-0000-4000-8000-0000000000A1") ?? UUID()
    nonisolated static let lakeAssetID = UUID(uuidString: "6E55E5E5-0000-4000-8000-0000000000A2") ?? UUID()

    static let bergen = Spot(latitude: 60.3975, longitude: 5.3238)
    static let lake = Spot(latitude: 61.4996, longitude: 8.6420)

    static func game(
      turn: UUID,
      points: Int = 28_640,
      mine: Int = 15_210,
      rounds: Int = 6,
      version: Int = 7
    ) -> RemoteGuessMySpotGame {
      RemoteGuessMySpotGame(
        id: gameID,
        turnUserID: turn,
        turnStartedAt: Fixture.now,
        sharedPoints: points,
        myPoints: min(mine, points),
        partnerPoints: max(0, points - mine),
        roundCount: rounds,
        version: version,
        createdByUserID: Fixture.me,
        createdAt: Fixture.now,
        updatedAt: Fixture.now
      )
    }

    static func round(
      id: UUID = roundID,
      number: Int = 6,
      sender: UUID,
      photo: UUID,
      spot: Spot?,
      place: String?,
      takenOn: String?,
      guess: Spot? = nil,
      seen: Bool = false
    ) -> RemoteGuessMySpotRound {
      let distance = spot.flatMap { spot in guess.map { GuessMySpotRules.distanceMeters($0, spot) } }
      var round = RemoteGuessMySpotRound(
        id: id,
        roundNumber: number,
        senderUserID: sender,
        guesserUserID: sender == Fixture.me ? Fixture.partner : Fixture.me,
        photoMediaAssetID: photo,
        photoWidth: 1_600,
        photoHeight: 1_200,
        spotLatitude: spot?.latitude,
        spotLongitude: spot?.longitude,
        placeName: place,
        takenOn: takenOn,
        sentAt: Fixture.now.addingTimeInterval(-3_600),
        distanceM: distance,
        points: distance.map(GuessMySpotRules.points(distanceMeters:)),
        guessedAt: guess == nil ? nil : Fixture.now.addingTimeInterval(-60),
        myRevealSeenAt: seen ? Fixture.now : nil
      )
      round.guess = guess
      return round
    }

    static func state(game: RemoteGuessMySpotGame?, current: RemoteGuessMySpotRound? = nil) -> RemoteGuessMySpotState {
      RemoteGuessMySpotState(
        userID: Fixture.me,
        partnerUserID: Fixture.partner,
        coupleID: DeveloperScenarioFixture.coupleID,
        dataEpoch: "",
        game: game,
        currentRound: current,
        previousRound: nil
      )
    }

    private static func harbor(
      sender: UUID,
      hidden: Bool = false,
      guess: Spot? = nil,
      seen: Bool = false
    ) -> RemoteGuessMySpotRound {
      round(
        sender: sender,
        photo: harborAssetID,
        spot: hidden ? nil : bergen,
        place: hidden ? nil : "Bergen, Norway",
        takenOn: hidden ? nil : "2025-07-14",
        guess: guess,
        seen: seen
      )
    }

    private static func lakeRound(
      sender: UUID,
      hidden: Bool = false,
      guess: Spot? = nil,
      seen: Bool = false
    ) -> RemoteGuessMySpotRound {
      round(
        sender: sender,
        photo: lakeAssetID,
        spot: hidden ? nil : lake,
        place: hidden ? nil : "Gjende, Norway",
        takenOn: hidden ? nil : "2024-08-03",
        guess: guess,
        seen: seen
      )
    }

    /// A reveal: the round is guessed, and the points are in the total already.
    private static func reveal(_ round: RemoteGuessMySpotRound) -> RemoteGuessMySpotState {
      let nextSender = round.guesserUserID
      // Only the guesser scores, so the round's points go to their own total.
      let points = round.knownPoints ?? 0
      let mine = round.guesserUserID == Fixture.me ? 15_210 + points : 15_210
      return state(game: game(turn: nextSender, points: 28_640 + points, mine: mine), current: round)
    }

    static func state(for scenario: DeveloperScenario) -> RemoteGuessMySpotState? {
      switch scenario {
      case .guessMySpotFirstTurn:
        return state(game: game(turn: Fixture.me, points: 0, mine: 0, rounds: 0))
      case .guessMySpotCheckFound, .guessMySpotCheckMissing:
        return state(game: game(turn: Fixture.me), current: lakeRound(sender: Fixture.partner, guess: lake, seen: true))
      case .guessMySpotWaitChoosing:
        return state(game: game(turn: Fixture.partner), current: harbor(sender: Fixture.me, guess: bergen, seen: true))
      case .guessMySpotWaitLive, .guessMySpotWaitLater:
        return state(game: game(turn: Fixture.partner), current: harbor(sender: Fixture.me))
      case .guessMySpotGuess, .guessMySpotRevealHeld:
        return state(game: game(turn: Fixture.me), current: lakeRound(sender: Fixture.partner, hidden: true))
      case .guessMySpotRevealSpotOn, .guessMySpotRevealClose, .guessMySpotRevealFar, .guessMySpotRevealWorld:
        return guessing(revealed(for: scenario))
      default:
        return revealed(for: scenario) ?? hubState(for: scenario)
      }
    }

    /// The guesser-side reveals open on the guess, with the pin already dropped, and
    /// the server's answer arrives a moment later (`DeveloperGuessMySpotScenarioView`).
    /// So the recording shows the photo leave and the build-up, as on a phone.
    static let stagedReveals: Set<DeveloperScenario> = [
      .guessMySpotRevealSpotOn, .guessMySpotRevealClose, .guessMySpotRevealFar, .guessMySpotRevealWorld,
    ]

    /// The same round before the guess: the spot, place and date hidden, at an older version.
    private static func guessing(_ revealed: RemoteGuessMySpotState?) -> RemoteGuessMySpotState? {
      guard let revealed, var round = revealed.currentRound else { return nil }
      round.spotLatitude = nil
      round.spotLongitude = nil
      round.placeName = nil
      round.takenOn = nil
      round.guess = nil
      round.distanceM = nil
      round.points = nil
      round.guessedAt = nil
      return state(game: game(turn: Fixture.me, version: 6), current: round)
    }

    static func revealed(for scenario: DeveloperScenario) -> RemoteGuessMySpotState? {
      switch scenario {
      case .guessMySpotRevealSpotOn:
        // About 460 m from Bryggen.
        reveal(harbor(sender: Fixture.partner, guess: Spot(latitude: 60.3943, longitude: 5.3290)))
      case .guessMySpotRevealClose:
        // About 110 km south-east of the lake.
        reveal(lakeRound(sender: Fixture.partner, guess: Spot(latitude: 60.75, longitude: 9.95)))
      case .guessMySpotRevealFar:
        reveal(harbor(sender: Fixture.partner, guess: Spot(latitude: 41.9028, longitude: 12.4964)))
      case .guessMySpotRevealWorld:
        reveal(harbor(sender: Fixture.partner, guess: Spot(latitude: -33.8688, longitude: 151.2093)))
      case .guessMySpotRevealSender:
        reveal(harbor(sender: Fixture.me, guess: Spot(latitude: 60.3400, longitude: 5.2200)))
      default:
        nil
      }
    }

    private static func hubState(for scenario: DeveloperScenario) -> RemoteGuessMySpotState? {
      switch scenario {
      case .guessMySpotHistory:
        return state(game: game(turn: Fixture.me, points: 48_210, rounds: 12))
      case .gamesHubYourTurn:
        return state(game: game(turn: Fixture.me), current: lakeRound(sender: Fixture.partner, hidden: true))
      case .gamesHubWaiting:
        return state(game: game(turn: Fixture.partner), current: harbor(sender: Fixture.me))
      default:
        // The other hub scenarios show the card of a couple that has not played yet.
        return scenario.rawValue.hasPrefix("games-hub") ? state(game: nil) : nil
      }
    }

    static func cache(for scenario: DeveloperScenario) -> InMemoryGuessMySpotCache {
      InMemoryGuessMySpotCache(
        state: state(for: scenario),
        history: scenario == .guessMySpotHistory ? history() : nil,
        ownerUserID: Fixture.me
      )
    }

    /// Sets this game's dependency fields, so its scenarios and the hub scenarios show it.
    static func configured(_ base: GamesDependencies, for scenario: DeveloperScenario) -> GamesDependencies {
      var dependencies = base
      dependencies.guessMySpotGateway = DeveloperGuessMySpotGateway()
      dependencies.guessMySpotCache = cache(for: scenario)
      dependencies.guessMySpotPlaceNamer = FixedGuessMySpotPlaceNamer(
        name: "Bergen, Norway",
        city: "Bergen",
        countryCode: "NO"
      )
      dependencies.makeGuessMySpotLive = { makeLive(for: scenario, coupleID: $0) }
      // Norway, as for a phone set to Norway that doesn't share its location.
      dependencies.guessMySpotHomeArea = FixedGuessMySpotHomeArea(area: GuessMySpotArea(
        center: Spot(latitude: 64.5, longitude: 12.0),
        meters: LiveGuessMySpotHomeArea.countryMeters
      ))
      dependencies.memoryPhotos = DeveloperGuessMySpotPhotoProvider(fallback: dependencies.memoryPhotos)
      return dependencies
    }

    // MARK: Photos

    static func photoData(_ resource: ImageResource) -> Data {
      UIImage(resource: resource).jpegData(compressionQuality: 0.85) ?? Data()
    }

    /// A picked photo, as the check shows it.
    static func draft(spot: Spot?) -> GuessMySpotDraft? {
      let image = UIImage(resource: spot == nil ? .guessMySpotScenarioLake : .guessMySpotScenarioHarbor)
      guard let prepared = GuessMySpotPhotoReader.prepare(image.jpegData(compressionQuality: 0.85) ?? Data()) else {
        return nil
      }
      return GuessMySpotDraft(
        roundID: UUID(),
        photo: prepared,
        image: image,
        spot: spot,
        place: spot == nil ? nil : GuessMySpotPlace(name: "Bergen, Norway", city: "Bergen", countryCode: "NO")
      )
    }

  }

  // MARK: - Live room

  extension DeveloperGuessMySpotScenarioFactory {
    /// The role Robin's phone says it is in, or nil when Robin is away.
    private static func partnerRole(in scenario: DeveloperScenario) -> WidgetLivePresence.Role? {
      switch scenario {
      case .guessMySpotWaitChoosing: .choosing
      case .guessMySpotWaitLive: .watching
      case .guessMySpotGuess, .guessMySpotCheckFound, .guessMySpotCheckMissing: .present
      default: nil
      }
    }

    /// What Robin's map shows while Robin guesses live, from Oslo zooming in toward Bergen.
    private static let liveViews: [GuessMySpotLiveMapView] = [
      (Spot(latitude: 59.91, longitude: 10.75), 400_000.0),
      (Spot(latitude: 61.2, longitude: 7.1), 250_000.0),
      (Spot(latitude: 60.55, longitude: 5.6), 60_000.0),
      (Spot(latitude: 60.41, longitude: 5.35), 8_000.0),
    ].map { spot, meters in
      let center = MKMapPoint(spot.location)
      let side = meters * MKMapPointsPerMeterAtLatitude(spot.latitude)
      return GuessMySpotLiveMapView(
        MKMapRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
        satellite: false
      )
    }

    /// The live room, with Robin already in it when the scenario calls for it. No
    /// relay is involved: Robin's messages are fed in directly.
    static func makeLive(for scenario: DeveloperScenario, coupleID: UUID) -> WidgetLiveDrawing? {
      let connection = WidgetLiveConnection(coupleID: coupleID, ticketProvider: { _ in nil })
      let live = WidgetLiveDrawing(
        connection: connection,
        role: .present,
        presence: WidgetLivePresence(countsLatestHelloOnly: true)
      )
      guard let role = partnerRole(in: scenario) else { return live }
      let taps = scenario == .guessMySpotWaitLive
      let picks = scenario == .guessMySpotWaitChoosing
      Task { @MainActor [weak live] in
        var step = 0
        while let live {
          if live.partnerActivity == .away {
            connection.onMessage?(WidgetLiveMessage(type: .welcome, id: "me", peers: 1))
            connection.onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: role.rawValue))
          }
          if taps {
            feed(.guessMap(roundID: roundID, view: liveViews[step % liveViews.count]), to: live)
            step += 1
          }
          // Robin picks the harbor photo after a moment.
          if picks, step == 1,
             let jpeg = await GuessMySpotPhotoPreview.jpeg(from: photoData(.guessMySpotScenarioHarbor)) {
            feed(.photoPreview(roundID: roundID, jpeg: jpeg), to: live)
          }
          if picks { step += 1 }
          try? await Task.sleep(for: .seconds(taps ? 2.2 : 2))
        }
      }
      return live
    }

    private static func feed(_ message: GuessMySpotLiveMessage, to live: WidgetLiveDrawing) {
      let envelope = GameLiveEnvelope(game: GuessMySpotLiveMessage.game, message: message)
      if let data = try? JSONEncoder().encode(envelope) {
        live.connection.onGameData?(data)
      }
    }
  }

#endif
