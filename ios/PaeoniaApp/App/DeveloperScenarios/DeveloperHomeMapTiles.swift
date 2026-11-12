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
}
#endif
