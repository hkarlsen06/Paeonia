import Foundation

/// What a pin on the map stands for.
nonisolated enum MemoryMapEntryKind: Hashable, Sendable {
    case memory
    /// A guessed round of Guess my spot: its photo at the real spot. Its card says it
    /// came from the game and opens the round. Rounds never count in the totals.
    case guessMySpotRound
}

/// One memory, or one Guess my spot round, on the map.
nonisolated struct MemoryMapEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The memory's title, or the round's place name.
    let title: String
    /// Couple-local `yyyy-MM-dd`. For a round, the day its photo was taken.
    let memoryDate: String
    let place: MemoryPlace
    /// The first photo, shown on the pin. Nil shows the heart tile.
    let photoAssetID: UUID?
    var kind: MemoryMapEntryKind = .memory
}

/// What the map shows, worked out from the timeline. Pure, so it is unit-tested.
nonisolated struct MemoriesMapContent: Equatable, Sendable {
    /// Memories with a place and Guess my spot rounds, newest first like the timeline.
    let placed: [MemoryMapEntry]
    /// Memories without one, newest first.
    let unplaced: [MemoryRecord]

    /// `rounds` are Guess my spot rounds, as `MemoryMapEntry` values of that kind.
    init(records: [MemoryRecord], rounds: [MemoryMapEntry] = []) {
        var placed: [MemoryMapEntry] = []
        var unplaced: [MemoryRecord] = []
        for record in records {
            let snapshot = record.snapshot
            guard let place = snapshot.place else {
                unplaced.append(record)
                continue
            }
            placed.append(MemoryMapEntry(
                id: snapshot.memoryID,
                title: snapshot.title ?? "",
                memoryDate: snapshot.memoryDate,
                place: place,
                photoAssetID: snapshot.visibleMediaAssetIDs.first
            ))
        }
        // Newest first. On the same day a memory comes before a round.
        self.placed = (placed + rounds).enumerated().sorted { lhs, rhs in
            guard lhs.element.memoryDate == rhs.element.memoryDate else {
                return lhs.element.memoryDate > rhs.element.memoryDate
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        self.unplaced = unplaced
    }

    /// The memories with a place, without the game's rounds.
    var placedMemories: [MemoryMapEntry] {
        placed.filter { $0.kind == .memory }
    }

    /// Countries and cities of memories only. Game rounds don't count.
    var totals: MemoryPlaceTotals {
        MemoryPlaceTotals(places: placedMemories.map(\.place))
    }
}

/// "4 countries · 11 cities". A city is a city name within a country, so Paris, Texas
/// and Paris, France count twice. Places with no city or country don't count toward that one.
nonisolated struct MemoryPlaceTotals: Equatable, Sendable {
    let countries: Int
    let cities: Int

    init(places: [MemoryPlace]) {
        countries = Set(places.compactMap(\.countryCode)).count
        cities = Set(places.compactMap { place in
            place.city.map { "\($0.lowercased())|\(place.countryCode ?? "")" }
        }).count
    }

    /// One country and one city reads as a small number rather than a milestone, so the
    /// line waits for a second city.
    var isWorthShowing: Bool {
        cities >= 2
    }
}

nonisolated enum MemoryClusterBadge {
    /// The count on a cluster. Three digits don't fit the badge.
    static func label(count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

nonisolated enum MemoryPinEntrance {
    /// How long one pin takes to pop in.
    static let pinDuration: TimeInterval = 0.32
    /// The whole entrance, first pin start to last pin end, never runs longer than this.
    static let totalDuration: TimeInterval = 0.6

    /// When each of `count` pins starts. Few pins step 50 ms apart. Many pins step
    /// closer together, so 40 pins still finish within `totalDuration`.
    static func delays(count: Int) -> [TimeInterval] {
        guard count > 1 else { return Array(repeating: 0, count: max(count, 0)) }
        let step = min(0.05, (totalDuration - pinDuration) / Double(count - 1))
        return (0..<count).map { Double($0) * step }
    }
}

extension MemoriesViewModel {
    /// Places on the couple's memories, newest first, each spot once. The place sheet
    /// lists them as "Places you've used".
    var knownPlaces: [MemoryPlace] {
        var places: [MemoryPlace] = []
        for record in timeline.flatMap(\.memories) {
            guard let place = record.snapshot.place, !places.contains(where: place.isSameSpot) else { continue }
            places.append(place)
        }
        return places
    }

    var mapContent: MemoriesMapContent {
        mapContent(rounds: [])
    }

    func mapContent(rounds: [MemoryMapEntry]) -> MemoriesMapContent {
        MemoriesMapContent(records: timeline.flatMap(\.memories), rounds: rounds)
    }
}
