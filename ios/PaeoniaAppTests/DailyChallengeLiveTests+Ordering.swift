import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

extension DailyChallengeLiveTests {
    @Test func shuffleResponseThatIsOlderThanALiveResultDoesNotOverwriteIt() async throws {
        // Whole seconds, so the row survives the JSON round trip of the live feed unchanged.
        let endsAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded() + 3_600)
        let stale = row(dayID: dayID, endsAt: endsAt, partnerAnswered: false)
        let cache = LockedSnapshotCache()
        let clock = DailyChallengeLiveWriteClock()
        let gateway = GatedShuffleGateway(response: stale)
        let service = DailyChallengeService(
            gateway: gateway,
            locale: Locale(identifier: "en_US"),
            cache: cache,
            liveWrites: clock
        )
        let transport = DailyPushTransport()
        let session = SyncSession(userID: user, activeCoupleID: UUID())
        let feed = DailyChallengeLiveFeed(cache: cache, liveWrites: clock)
        let feedTask = Task { await feed.run(session: session, live: LiveQueryService(transport: transport)) }
        let currentUser = user

        // The shuffle request is in flight when the partner answers.
        let shuffle = Task {
            try await service.shuffleQuestion(
                currentUserID: currentUser,
                slotNumber: 1,
                operation: dailyFixedClientOperation()
            )
        }
        #expect(await waitUntil { await gateway.hasStarted() })
        let answered = row(dayID: dayID, endsAt: endsAt, partnerAnswered: true, revealed: true)
        try await transport.push([answered], to: "daily:get_today_daily_challenge_snapshot")
        #expect(await waitUntil { cache.load(ownerUserID: currentUser) == answered })
        await gateway.open()

        let result = try await shuffle.value
        #expect(result.snapshot.questions.first?.canViewPartnerAnswer == true)
        #expect(cache.load(ownerUserID: user) == answered)
        feedTask.cancel()
        await feedTask.value
    }

    @Test func responseIsSavedWhenNoLiveResultLandedWhileItWasInFlight() async throws {
        let endsAt = Date().addingTimeInterval(3_600)
        let cache = LockedSnapshotCache()
        let clock = DailyChallengeLiveWriteClock()
        // A live result from before the request does not make the response stale.
        clock.recordLiveWrite(row(dayID: dayID, endsAt: endsAt), ownerUserID: user, cache: cache)
        let response = row(dayID: dayID, endsAt: endsAt, partnerAnswered: true)
        let service = DailyChallengeService(
            gateway: GatedShuffleGateway(response: response, isOpen: true),
            locale: Locale(identifier: "en_US"),
            cache: cache,
            liveWrites: clock
        )

        _ = try await service.shuffleQuestion(
            currentUserID: user,
            slotNumber: 1,
            operation: dailyFixedClientOperation()
        )

        #expect(cache.load(ownerUserID: user) == response)
    }

    @Test func responseForANewDayReplacesALiveResultOfTheOldDay() throws {
        let endsAt = Date().addingTimeInterval(3_600)
        let newDayID = dailyFixedUUID("a1a1a1a1-0000-0000-0000-0000000000d2")
        let cache = LockedSnapshotCache()
        let clock = DailyChallengeLiveWriteClock()
        let response = row(dayID: newDayID, endsAt: endsAt.addingTimeInterval(86_400))
        let start = clock.count(ownerUserID: user)
        clock.recordLiveWrite(row(dayID: dayID, endsAt: endsAt), ownerUserID: user, cache: cache)

        let used = clock.saveResponse(response, ownerUserID: user, since: start, cache: cache)

        #expect(used == response)
        #expect(cache.load(ownerUserID: user) == response)
    }

    @Test func responseForAnOlderDayKeepsTheNewerLiveResult() throws {
        let endsAt = Date().addingTimeInterval(3_600)
        let yesterdayID = dailyFixedUUID("a1a1a1a1-0000-0000-0000-0000000000d3")
        let cache = LockedSnapshotCache()
        let clock = DailyChallengeLiveWriteClock()
        let live = row(dayID: dayID, endsAt: endsAt)
        let start = clock.count(ownerUserID: user)
        clock.recordLiveWrite(live, ownerUserID: user, cache: cache)

        let used = clock.saveResponse(
            row(dayID: yesterdayID, endsAt: endsAt.addingTimeInterval(-86_400)),
            ownerUserID: user,
            since: start,
            cache: cache
        )

        #expect(used == live)
        #expect(cache.load(ownerUserID: user) == live)
    }

    @Test func feedReturnsAtOnceWithoutAnActiveCouple() async {
        let transport = DailyPushTransport()
        let feed = DailyChallengeLiveFeed(cache: LockedSnapshotCache())

        await feed.run(
            session: SyncSession(userID: user, activeCoupleID: nil),
            live: LiveQueryService(transport: transport)
        )

        #expect(transport.openedPaths.value.isEmpty)
    }

    @Test func aResponseInFlightDuringAPrivacyPurgeIsNotWrittenBack() {
        let cache = LockedSnapshotCache()
        let clock = DailyChallengeLiveWriteClock()
        let response = row(dayID: dayID, endsAt: Date().addingTimeInterval(3_600))
        let start = clock.count(ownerUserID: user)

        // Sign-out or leaving the relationship wipes the cache while a load is out.
        clock.notePurge()
        cache.clearAll()
        let used = clock.saveResponse(response, ownerUserID: user, since: start, cache: cache)

        #expect(used == response)
        #expect(cache.load(ownerUserID: user) == nil)
    }
}
