import Foundation
import Testing
@testable import PaeoniaApp

/// A server that keeps recap rows: `ensureRecap` finishes the due one, and a start date change deletes them all.
nonisolated private final class RecapServer: RecapServing, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [AnniversaryRecap] = []
    private var years = 1

    func startDateChanged(years: Int) {
        lock.withLock {
            rows = []
            self.years = years
        }
    }

    // swiftlint:disable async_without_await
    func fetchRecaps() async throws -> [AnniversaryRecap] { lock.withLock { rows } }

    func ensureRecap() async throws -> AnniversaryRecap? {
        lock.withLock {
            if rows.isEmpty { rows = [RecapViewModelTests.recap(years: years)] }
            return rows[0]
        }
    }

    func fetchMoments(anniversaryDate _: String) async throws -> [LookBackItem] { [] }
    // swiftlint:enable async_without_await
}

nonisolated private final class NoRecapCache: RecapCaching, @unchecked Sendable {
    func load(ownerUserID _: UUID, coupleID _: UUID?) -> RecapCacheEntry? { nil }
    func purgeCount() -> Int { 0 }
    func save(_: RecapCacheEntry, ownerUserID _: UUID, unlessPurgedSince _: Int) -> Bool { true }
    func clearAll() {}
}

@MainActor
struct RecapViewModelTests {
    private nonisolated static let anniversary = Date(timeIntervalSince1970: 1_794_398_400) // 2026-11-11T12:00:00Z

    nonisolated static func recap(years: Int) -> AnniversaryRecap {
        AnniversaryRecap(
            anniversaryDate: "2026-11-11", years: years, periodStart: "2025-11-11", periodEnd: "2026-11-11",
            sinceJoined: false, countedOn: "2026-11-11",
            counts: .init(
                answeredTogether: 3, drawings: 0, memories: 0, memoryPhotos: 0, stories: 0, letters: 0, visits: 0,
                visitDays: 0, gameDays: 0, heartsAllTime: 0, longestStreakAllTime: 0
            )
        )
    }

    /// Fixing the start year on the anniversary deletes the recap on the server, and the new date has the
    /// same anniversary day. The Us tab asks again and shows the new recap.
    @Test func aChangedStartDateOnTheAnniversaryAsksForTheRecapAgain() async {
        let server = RecapServer()
        let model = RecapViewModel(service: server, cache: NoRecapCache(), now: { Self.anniversary })
        let user = UUID(), couple = UUID()

        await model.configure(userID: user, coupleID: couple, startedOn: "2025-11-11")
        #expect(model.homeRecap?.years == 1)
        server.startDateChanged(years: 7)
        await model.configure(userID: user, coupleID: couple, startedOn: "2019-11-11")
        #expect(model.homeRecap?.years == 7)
    }

    /// The anniversary push on a cold launch, before the recap is counted, with the start date loading
    /// after the Us tab's first read. The link waits for a read made with the start date.
    @Test func aLinkWaitsForAReadThatKnowsTheStartDate() async {
        let model = RecapViewModel(service: RecapServer(), cache: NoRecapCache(), now: { Self.anniversary })
        let user = UUID(), couple = UUID()

        #expect(await model.presentLink("2026-11-11", startedOn: nil, isCurrent: { true }))
        await model.configure(userID: user, coupleID: couple, startedOn: nil)
        #expect(model.presented == nil)
        await model.configure(userID: user, coupleID: couple, startedOn: "2025-11-11")
        #expect(model.presented?.anniversaryDate == "2026-11-11")
    }
}
