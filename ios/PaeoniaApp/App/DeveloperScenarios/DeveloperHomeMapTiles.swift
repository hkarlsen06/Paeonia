#if DEBUG
import Foundation
import SwiftUI

/// How OpenFreeMap answers Home's map in a local flow.
nonisolated enum DeveloperHomeMapTiles: Sendable {
    case live
    /// The map reports a delay while its endpoints answer successfully.
    case slowRender
    /// OpenFreeMap can't be reached while the phone is online, so Home falls back to the map card.
    case outage
    /// The phone has no connection.
    case offline
    /// OpenFreeMap fails at first and answers the next check: when the app comes back to the
    /// screen, or a minute later. Opening a sheet first shows that Home waits for it to close.
    case recovery

    private static let unreachableStyle = URL(string: "https://tiles.openfreemap.invalid/styles/dark")!

    @MainActor
    func makeStatus() -> HomeMapTileStatus {
        switch self {
        case .live:
            return HomeMapTileStatus()
        case .slowRender:
            let status = HomeMapTileStatus { _ in }
            Task { await status.mapDidNotLoad() }
            return status
        case .outage:
            return HomeMapTileStatus(styleURL: Self.unreachableStyle)
        case .offline:
            return HomeMapTileStatus(styleURL: Self.unreachableStyle) { _ in
                throw URLError(.notConnectedToInternet)
            }
        case .recovery:
            var firstCheck = true
            let status = HomeMapTileStatus { _ in
                if firstCheck {
                    firstCheck = false
                    throw URLError(.badServerResponse)
                }
            }
            Task { await status.mapDidNotLoad() }
            return status
        }
    }
}

nonisolated extension DeveloperScenario {
    static let homeMapSlowRender = DeveloperScenario(
      "home-map-slow-render", "Home map · slow render",
      "The map reports a loading delay while its endpoints answer", .relationship
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .locationFirst, mapTiles: .slowRender) }
    static let homeMapOutage = DeveloperScenario(
      "home-map-outage", "Home map · OpenFreeMap down",
      "The map can't load while online, so Home switches to the map card", .relationship
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .locationFirst, mapTiles: .outage) }
    static let homeMapOffline = DeveloperScenario(
      "home-map-offline", "Home map · offline",
      "No connection, so the map stays blank with the avatars in their places", .relationship
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .locationFirst, mapTiles: .offline) }
    static let homeMapRecovery = DeveloperScenario(
      "home-map-recovery", "Home map · OpenFreeMap back",
      "An endpoint check fails, and OpenFreeMap answers again on return to the app", .relationship
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .locationFirst, mapTiles: .recovery) }
    /// A couple that lives mostly north and south of each other, so the map turns to fit them.
    static let homeMapApart = DeveloperScenario(
      "home-map-apart", "Home map · far apart",
      "Oslo and Tromsø, 1,150 km apart and mostly north and south of each other", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    /// Robin's place changes while Home is open, so the map and the distance line move.
    static let homeMapPartnerMoves = DeveloperScenario(
      "home-map-partner-moves", "Home map · partner moves",
      "Robin goes from Tromsø to Trondheim, Lillehammer, Oslo and Bergen, 3.5 s apart", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    /// Home without location sharing, then sharing turns on and both places arrive.
    static let homeMapShareLocation = DeveloperScenario(
      "home-map-share-location", "Home map · start sharing",
      "Alex in Oslo shares after 6 s, Robin is in Tromsø, and the map flies in 1.5 s later", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    /// The same while OpenFreeMap is down: Home keeps its layout without the world preview,
    /// and switches to the map card once both places arrive.
    static let homeMapShareLocationOutage = DeveloperScenario(
      "home-map-share-location-outage", "Home map · start sharing, OpenFreeMap down",
      "As home-map-share-location, but the map can't load, so the map card takes over", .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    /// Robin's game card leads the cards, then goes, so the cards under it move up.
    static let homePartnerLeavesGame = DeveloperScenario(
      "home-partner-leaves-game", "Home · partner leaves a game",
      "Robin's Draw & Guess card shows above the question of when you meet next, then Robin leaves after 10 s",
      .relationship
    ) { DeveloperPairedScenarioHost(scenario: $0) }
}
#endif
