import Foundation

// Guess my spot rounds on the Memories tab's "Our places" map. Each guessed round
// is a pin with its photo, and its card says it came from the game. Rounds never
// count in the map's countries and cities, which are about memories.
extension GuessMySpotHistoryViewModel {
    /// The guessed rounds as map entries, newest first.
    var memoryMapEntries: [MemoryMapEntry] {
        rounds.compactMap(Self.memoryMapEntry)
    }

    static func memoryMapEntry(_ round: RemoteGuessMySpotRound) -> MemoryMapEntry? {
        guard let spot = round.spot else { return nil }
        let name = round.placeName ?? String(localized: .guessMySpotHistorySomewhere)
        // The day the photo was taken, or the day it was guessed when the photo had none.
        let day = round.takenOn ?? round.guessedAt.map { MemoryTimeline.localDateString(for: $0) }
        return MemoryMapEntry(
            id: round.id,
            title: name,
            memoryDate: day ?? "",
            place: MemoryPlace(
                name: round.placeCity ?? name,
                latitude: spot.latitude,
                longitude: spot.longitude,
                city: round.placeCity,
                countryCode: round.placeCountryCode
            ),
            photoAssetID: round.photoMediaAssetID,
            kind: .guessMySpotRound
        )
    }

    /// Reads the map again whenever the game moves on (a guess, a seen reveal or a
    /// delete bumps its version) and when a delete hidden here leaves the queue, so a
    /// refused one comes back. Runs until the screen's task ends.
    func follow() async {
        guard let userID = currentUserID else { return }
        var version = await dependencies.guessMySpotCache.document(ownerUserID: userID).state?.game?.version
        for await _ in LocalStoreChanges.changes(in: .games) {
            guard !Task.isCancelled, currentUserID == userID else { return }
            let current = await dependencies.guessMySpotCache.document(ownerUserID: userID).state?.game?.version
            let settled = await hasSettledDeletes
            guard current != version || settled else { continue }
            version = current
            await load()
        }
    }
}
