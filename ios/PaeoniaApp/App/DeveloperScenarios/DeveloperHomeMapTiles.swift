#if DEBUG
import Foundation
import SwiftUI

/// How OpenFreeMap answers Home's map in a local flow. Each flow starts from its own empty
/// defaults, so an outage from one run never reaches the next or the real app.
nonisolated enum DeveloperHomeMapTiles: Sendable {
    case live
    /// OpenFreeMap can't be reached while the phone is online, so Home falls back to the map card.
    case outage
    /// The phone has no connection.
    case offline
    /// OpenFreeMap was down at the last launch and answers again a few seconds in.
    case recovery

    private static let unreachableStyle = URL(string: "https://tiles.openfreemap.invalid/styles/dark")!

    @MainActor
    func makeStatus() -> HomeMapTileStatus {
        let suite = "DeveloperHomeMapTiles"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Could not create isolated Home map scenario defaults")
        }
        defaults.removePersistentDomain(forName: suite)
        switch self {
        case .live:
            return HomeMapTileStatus(defaults: defaults)
        case .outage:
            return HomeMapTileStatus(styleURL: Self.unreachableStyle, defaults: defaults)
        case .offline:
            return HomeMapTileStatus(styleURL: Self.unreachableStyle, defaults: defaults) { _ in
                throw URLError(.notConnectedToInternet)
            }
        case .recovery:
            defaults.set(Date.now.addingTimeInterval(4), forKey: HomeMapTileStatus.retryAfterKey)
            return HomeMapTileStatus(defaults: defaults)
        }
    }
}

nonisolated extension DeveloperScenario {
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
      "Opens on the map card from the last outage, then OpenFreeMap answers and the map returns", .relationship
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .locationFirst, mapTiles: .recovery) }
}
#endif
