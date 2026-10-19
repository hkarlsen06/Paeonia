import Foundation

/// Pins that would overlap at the map's zoom, shown as one pin with a count.
nonisolated struct GuessMySpotCluster: Identifiable, Equatable, Sendable {
    /// The newest round's id, so a cluster keeps its id while it only grows or shrinks.
    let id: UUID
    /// Newest first, as the rounds came in.
    let roundIDs: [UUID]
    /// The newest round's spot. The pin stands on a real place, not on an average.
    let coordinate: GuessMySpotCoordinate
    /// Every member's spot, to zoom in on them.
    let spots: [GuessMySpotCoordinate]

    var count: Int { roundIDs.count }

    /// The members are all at about one spot, so zooming in would never split them.
    var isOneSpot: Bool {
        guard let first = spots.first else { return true }
        return spots.allSatisfy { GuessMySpotRules.distanceMeters($0, first) <= 300 }
    }
}

nonisolated enum GuessMySpotClustering {
    /// Groups pins that would overlap at the map's zoom. A pin joins the first
    /// cluster whose newest spot is less than a pin's size away, about a ninth of
    /// the visible height and a sixth of the width. Order is kept, so the first
    /// member of a cluster is the newest.
    /// ponytail: compares every pin with every cluster, fine for a couple's rounds.
    static func clusters(
        _ items: [(id: UUID, spot: GuessMySpotCoordinate)],
        latitudeDelta: Double,
        longitudeDelta: Double
    ) -> [GuessMySpotCluster] {
        let reachLatitude = max(latitudeDelta / 9, 1e-6)
        let reachLongitude = max(longitudeDelta / 6, 1e-6)
        var groups: [[(id: UUID, spot: GuessMySpotCoordinate)]] = []
        for item in items {
            let index = groups.firstIndex { group in
                abs(group[0].spot.latitude - item.spot.latitude) < reachLatitude
                    && abs(group[0].spot.longitude - item.spot.longitude) < reachLongitude
            }
            if let index {
                groups[index].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups.map { group in
            GuessMySpotCluster(
                id: group[0].id,
                roundIDs: group.map(\.id),
                coordinate: group[0].spot,
                spots: group.map(\.spot)
            )
        }
    }

    /// The count on a cluster. Three digits don't fit the badge.
    static func badge(count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}
