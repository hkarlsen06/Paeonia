import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct DailyChallengeLiveTests {
    let user = dailyFixedUUID("a1a1a1a1-0000-0000-0000-000000000001")
    let partner = dailyFixedUUID("a1a1a1a1-0000-0000-0000-000000000002")
    let dayID = dailyFixedUUID("a1a1a1a1-0000-0000-0000-0000000000d1")

    func row(
        dayID: UUID?,
        endsAt: Date?,
        partnerAnswered: Bool = false,
        revealed: Bool = false,
        streak: Int = 0
    ) -> DailyChallengeRemoteSnapshotRow {
        let instanceID = dailyFixedUUID("a1a1a1a1-0000-0000-0000-0000000000e1")
        let ownAnswerID = dailyFixedUUID("a1a1a1a1-0000-0000-0000-0000000000f1")
        let partnerAnswerID = dailyFixedUUID("a1a1a1a1-0000-0000-0000-0000000000f2")
        let questions: [DailyQuestionRow] = dayID == nil ? [] : [
            dailyQuestionRow(
                coupleDayID: dayID ?? UUID(),
                instanceID: instanceID,
                ownAnswerID: ownAnswerID,
                ownAnsweredAt: TestDailyChallengeIDs.answerDate,
                partnerAnswerID: partnerAnswered ? partnerAnswerID : nil,
                partnerAnsweredAt: partnerAnswered ? TestDailyChallengeIDs.answerDate : nil,
                canViewPartnerAnswer: revealed
            ),
        ]
        let details: [DailyAnswerDetailRow] = revealed ? [
            dailyAnswerDetail(answerUserID: user, answerID: ownAnswerID, isOwnAnswer: true, textBody: "A walk."),
            dailyAnswerDetail(
                answerUserID: partner,
                answerID: partnerAnswerID,
                isOwnAnswer: false,
                textBody: "Dinner."
            ),
        ] : []
        return DailyChallengeRemoteSnapshotRow(
            questions: questions,
            answerDetails: details,
            streak: CoupleStreakRow(
                currentCount: streak, longestCount: streak, lastQualifiedDate: nil,
                restoreAvailable: false, restorableCount: 0, restoreDeadline: nil
            ),
            generatedAt: Date(timeIntervalSince1970: 1_782_450_000),
            coupleDayID: dayID,
            endsAt: endsAt
        )
    }

    /// A view model whose one-shot load returns `today`, so a live result is the only change.
    func makeViewModel(
        cache: LockedSnapshotCache,
        today: DailyChallengeRemoteSnapshotRow
    ) -> (DailyChallengeViewModel, RecordingDailyChallengeService) {
        let loaded = today.loadResult(currentUserID: user, locale: Locale(identifier: "en_US"))
        let service = RecordingDailyChallengeService(snapshots: [loaded.snapshot], streak: loaded.streak)
        let viewModel = DailyChallengeViewModel(
            service: service,
            operationProvider: FixedDailyChallengeOperationProvider(),
            snapshotCache: cache
        )
        return (viewModel, service)
    }

    @Test func partnerAnswerRevealAndStreakAppearWithoutAReload() async throws {
        let endsAt = Date().addingTimeInterval(3_600)
        let cache = LockedSnapshotCache()
        let initial = row(dayID: dayID, endsAt: endsAt, partnerAnswered: false, streak: 2)
        cache.save(initial, ownerUserID: user)
        let (viewModel, service) = makeViewModel(cache: cache, today: initial)
        let transport = DailyPushTransport()
        let session = SyncSession(userID: user, activeCoupleID: UUID())
        let feed = DailyChallengeLiveFeed(cache: cache)
        let task = Task { await feed.run(session: session, live: LiveQueryService(transport: transport)) }

        await viewModel.configure(currentUserID: user)
        #expect(viewModel.snapshot.questions.first?.canViewPartnerAnswer == false)

        try await transport.push(
            [row(dayID: dayID, endsAt: endsAt, partnerAnswered: true, revealed: true, streak: 3)],
            to: "daily:get_daily_challenge_snapshot"
        )

        let revealed = await waitForDaily {
            viewModel.snapshot.questions.first?.canViewPartnerAnswer == true && viewModel.streak.currentCount == 3
        }
        #expect(revealed)
        #expect(await service.loadCount == 1)
        #expect(transport.openedPaths.value == ["daily:get_daily_challenge_snapshot"])
        #expect(transport.openedArgs.value == [["p_couple_day_id": "\"\(dayID.uuidString.lowercased())\""]])
        task.cancel()
        await task.value
    }

    @Test func partnerStartingTheDayMovesTheFeedFromTodayToThatDay() async throws {
        let endsAt = Date().addingTimeInterval(3_600)
        let cache = LockedSnapshotCache()
        let (viewModel, _) = makeViewModel(cache: cache, today: row(dayID: nil, endsAt: nil))
        let transport = DailyPushTransport()
        let session = SyncSession(userID: user, activeCoupleID: UUID())
        let feed = DailyChallengeLiveFeed(cache: cache)
        let task = Task { await feed.run(session: session, live: LiveQueryService(transport: transport)) }
        await viewModel.configure(currentUserID: user)
        #expect(!viewModel.snapshot.hasAnyQuestions)

        try await transport.push([row(dayID: nil, endsAt: nil)], to: "daily:get_today_daily_challenge_snapshot")
        try await transport.push([row(dayID: dayID, endsAt: endsAt)], to: "daily:get_today_daily_challenge_snapshot")

        #expect(await waitForDaily { viewModel.snapshot.hasAnyQuestions })
        #expect(await waitUntil {
            transport.openedPaths.value == [
                "daily:get_today_daily_challenge_snapshot",
                "daily:get_daily_challenge_snapshot",
            ]
        })
        #expect(transport.openedArgs.value.first?["p_day_key"] != nil)
        task.cancel()
        await task.value
    }

    @Test func dayEndOpensANewTodaySubscriptionWithADifferentKey() async throws {
        let startOfTest = Date(timeIntervalSince1970: 1_800_000_000)
        let endsAt = startOfTest.addingTimeInterval(3_600)
        let clock = LockedBox(startOfTest)
        let dayEnded = LockedBox(false)
        let sleeps = LockedBox(0)
        let cache = LockedSnapshotCache()
        let initial = row(dayID: dayID, endsAt: endsAt, partnerAnswered: true)
        cache.save(initial, ownerUserID: user)
        let (viewModel, _) = makeViewModel(cache: cache, today: initial)
        let transport = DailyPushTransport()
        let session = SyncSession(userID: user, activeCoupleID: UUID())
        let feed = DailyChallengeLiveFeed(
            cache: cache,
            now: { clock.value },
            sleep: { _ in
                // The first sleep is the wait for the day to end. Later ones wait for the renewal time.
                let isDayEndWait = sleeps.value == 0
                sleeps.mutate { $0 += 1 }
                if isDayEndWait {
                    _ = await waitUntil { dayEnded.value }
                    clock.mutate { $0 = endsAt.addingTimeInterval(1) }
                } else {
                    try await Task.sleep(for: .seconds(3_600))
                }
            }
        )
        let task = Task { await feed.run(session: session, live: LiveQueryService(transport: transport)) }
        await viewModel.configure(currentUserID: user)
        #expect(viewModel.snapshot.hasAnyQuestions)

        // The old day is still on screen until its end passes.
        #expect(await waitUntil { transport.openedPaths.value == ["daily:get_daily_challenge_snapshot"] })
        dayEnded.mutate { $0 = true }
        #expect(await waitUntil { transport.openedPaths.value.count == 2 })
        #expect(transport.openedPaths.value.last == "daily:get_today_daily_challenge_snapshot")
        let key = try #require(transport.openedArgs.value.last?["p_day_key"])
        // Args arrive JSON encoded, so the string keeps its quotes.
        #expect(UUID(uuidString: key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) != nil)

        // The new day has no couple day yet, and nothing starts one for the user.
        try await transport.push([row(dayID: nil, endsAt: nil)], to: "daily:get_today_daily_challenge_snapshot")
        #expect(await waitForDaily { !viewModel.snapshot.hasAnyQuestions })
        #expect(viewModel.homeCardState.kind == .noChallenge)
        #expect(transport.openedPaths.value.count == 2)
        task.cancel()
        await task.value
    }
}
