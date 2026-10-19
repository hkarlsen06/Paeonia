import Foundation
import Testing
@testable import PaeoniaApp

/// "Our guesses": the clusters, the score by play style, deleting a round, and the
/// rounds as pins on the Memories tab's map.
@MainActor
struct GuessMySpotMapTests {
    let bergen = GuessMySpotCoordinate(latitude: 60.3913, longitude: 5.3221)
    let bryggen = GuessMySpotCoordinate(latitude: 60.3975, longitude: 5.3245)
    let oslo = GuessMySpotCoordinate(latitude: 59.9139, longitude: 10.7522)

    // MARK: Clusters

    @Test func pinsInOneCellBecomeOneClusterAtTheNewestSpot() {
        let newest = UUID()
        let older = UUID()
        let far = UUID()
        let clusters = GuessMySpotClustering.clusters(
            [(newest, bergen), (far, oslo), (older, bryggen)],
            latitudeDelta: 18,
            longitudeDelta: 30
        )
        #expect(clusters.count == 2)
        #expect(clusters.first?.id == newest)
        #expect(clusters.first?.roundIDs == [newest, older])
        #expect(clusters.first?.coordinate == bergen)
        #expect(clusters.first?.isOneSpot == false)
        #expect(clusters.last?.roundIDs == [far])
    }

    @Test func zoomingInSplitsAClusterUnlessItIsOneSpot() {
        let items = [(UUID(), bergen), (UUID(), bryggen)]
        #expect(GuessMySpotClustering.clusters(items, latitudeDelta: 0.01, longitudeDelta: 0.01).count == 2)
        let sameSpot = [(UUID(), bergen), (UUID(), GuessMySpotCoordinate(latitude: 60.3914, longitude: 5.3222))]
        let cluster = GuessMySpotClustering.clusters(sameSpot, latitudeDelta: 18, longitudeDelta: 30)
        #expect(cluster.first?.isOneSpot == true)
    }

    @Test func theBadgeStopsAt99() {
        #expect(GuessMySpotClustering.badge(count: 2) == "2")
        #expect(GuessMySpotClustering.badge(count: 99) == "99")
        #expect(GuessMySpotClustering.badge(count: 100) == "99+")
    }

    // MARK: Score

    @Test func thePlayStyleChoosesTheScore() {
        let game = RemoteGuessMySpotGame(
            id: UUID(), turnUserID: GameFixture.me, turnStartedAt: GameFixture.now,
            sharedPoints: 9_000, myPoints: 4_000, partnerPoints: 5_000, roundCount: 2, version: 1,
            createdByUserID: GameFixture.me, createdAt: GameFixture.now, updatedAt: GameFixture.now
        )
        #expect(GuessMySpotScore(game: game, playStyle: .together) == .together(total: 9_000))
        #expect(GuessMySpotScore(game: game, playStyle: .against) == .against(mine: 4_000, partner: 5_000))
        #expect(GuessMySpotScore(game: nil, playStyle: .against).isEmpty)
    }

    @Test func theRevealCountsOnlyTheGuessersSideUp() {
        let score = GuessMySpotScore.against(mine: 4_000, partner: 5_000)
        #expect(score.counting(points: 3_000, counted: 0, guesserIsMe: true) == .against(mine: 1_000, partner: 5_000))
        #expect(score.counting(points: 3_000, counted: 1_000, guesserIsMe: false)
            == .against(mine: 4_000, partner: 3_000))
        #expect(score.counting(points: 3_000, counted: 3_000, guesserIsMe: true) == score)
        #expect(GuessMySpotScore.together(total: 100).counting(points: 500, counted: 0, guesserIsMe: true)
            == .together(total: 0))
    }

    // MARK: Deleting

    @Test func onlyTheSenderDeletesARoundBothHaveSeen() async throws {
        let cache = InMemoryGuessMySpotCache()
        let pending = InMemoryPendingSyncOperationRepository()
        let mine = round(sender: GameFixture.me, canDelete: true)
        let theirs = round(sender: GameFixture.partner, canDelete: true)
        let unseen = round(sender: GameFixture.me, canDelete: false)
        await cache.saveHistory(
            history([mine, theirs, unseen]),
            ownerUserID: GameFixture.me,
            ticket: cache.historyTicket()
        )
        var dependencies = GamesTestEnvironment(state: nil).dependencies()
        dependencies.guessMySpotCache = cache
        dependencies.pendingOperationStore = pending
        let viewModel = GuessMySpotHistoryViewModel(dependencies: dependencies, participants: GameFixture.participants)
        await viewModel.load()
        #expect(viewModel.rounds.count == 3)

        #expect(await viewModel.delete(theirs) == false)
        #expect(await viewModel.delete(unseen) == false)
        #expect(await viewModel.delete(mine))
        #expect(viewModel.rounds.map(\.id) == [theirs.id, unseen.id])
        let queued = try await pending.inFlightOperations(ownerUserID: GameFixture.me, kind: .guessMySpotDeleteRound)
        #expect(queued.count == 1)
        #expect(await viewModel.hasSettledDeletes == false)

        // The server refused it: the round comes back on the next read, even one that fails.
        let operation = try #require(queued.first)
        try await pending.markTerminalFailure(
            clientOperationID: operation.operation.id, errorDescription: "no", at: GameFixture.now
        )
        #expect(await viewModel.hasSettledDeletes)
        await viewModel.load()
        #expect(Set(viewModel.rounds.map(\.id)) == [mine.id, theirs.id, unseen.id])
    }

    // MARK: The memory map

    @Test func aGuessedRoundIsAPinFromTheGame() throws {
        var guessed = round(sender: GameFixture.partner, canDelete: false)
        guessed.placeName = "Bryggen, Bergen"
        guessed.placeCity = "Bergen"
        guessed.placeCountryCode = "NO"
        guessed.takenOn = "2024-06-12"
        let entry = try #require(GuessMySpotHistoryViewModel.memoryMapEntry(guessed))
        #expect(entry.kind == .guessMySpotRound)
        #expect(entry.title == "Bryggen, Bergen")
        #expect(entry.memoryDate == "2024-06-12")
        #expect(entry.place.city == "Bergen")
        #expect(entry.photoAssetID == guessed.photoMediaAssetID)

        var noSpot = guessed
        noSpot.spotLatitude = nil
        #expect(GuessMySpotHistoryViewModel.memoryMapEntry(noSpot) == nil)
    }

    @Test func roundsShowOnTheMapButNeverCountAsPlaces() throws {
        var guessed = round(sender: GameFixture.me, canDelete: false)
        guessed.placeCity = "Bergen"
        guessed.placeCountryCode = "NO"
        let entry = try #require(GuessMySpotHistoryViewModel.memoryMapEntry(guessed))
        let content = MemoriesMapContent(records: [], rounds: [entry])
        #expect(content.placed == [entry])
        #expect(content.placedMemories.isEmpty)
        #expect(content.totals == MemoryPlaceTotals(places: []))
    }

    // MARK: Fixtures

    private func round(sender: UUID, canDelete: Bool) -> RemoteGuessMySpotRound {
        var round = RemoteGuessMySpotRound(
            id: UUID(), roundNumber: 1, senderUserID: sender,
            guesserUserID: sender == GameFixture.me ? GameFixture.partner : GameFixture.me,
            photoMediaAssetID: UUID(), photoWidth: 4, photoHeight: 3,
            spotLatitude: bergen.latitude, spotLongitude: bergen.longitude, sentAt: GameFixture.now,
            guessedAt: GameFixture.now, canDelete: canDelete
        )
        round.guess = oslo
        return round
    }

    private func history(_ rounds: [RemoteGuessMySpotRound]) -> RemoteGuessMySpotHistory {
        let none = RemoteGuessMySpotGuesserRecord(guesses: 0, closestM: nil, averageM: nil)
        return RemoteGuessMySpotHistory(
            rounds: rounds,
            records: RemoteGuessMySpotRecords(
                sharedPoints: 0, myPoints: 0, partnerPoints: 0, mine: none, partner: none
            )
        )
    }
}
