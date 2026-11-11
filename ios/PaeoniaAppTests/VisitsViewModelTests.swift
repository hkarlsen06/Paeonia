import Foundation
import Testing
@testable import PaeoniaApp

/// Covers when the person hears about a write the server refused for good, and when the hidden
/// "When do you meet next?" card comes back.
@MainActor
struct VisitsViewModelTests {
    private let owner = UUID()

    private func model(_ cache: InMemoryVisitsCache) -> VisitsViewModel {
        VisitsViewModel(
            cache: cache,
            pendingOperationStore: InMemoryPendingSyncOperationRepository(),
            operationProvider: DeveloperScenarioOperationProvider()
        )
    }

    @Test func aRefusalWaitsWhileTheAppIsInTheBackground() async {
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        let visits = model(cache)

        await visits.setActive(false)
        await visits.configure(ownerUserID: owner)
        #expect(visits.error == nil)
        #expect(visits.itemDraft.isEmpty)

        await visits.setActive(true)
        #expect(visits.error == .itemsNotAdded(["Ice skating"]))
        #expect(visits.itemDraft == "Ice skating")
    }

    @Test func aRefusalStaysOnThePhoneUntilAScreenShowedIt() async {
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        let visits = model(cache)
        await visits.setActive(true)
        await visits.configure(ownerUserID: owner)
        await visits.reload()

        #expect(visits.error == .itemsNotAdded(["Ice skating"]))
        #expect(await cache.state(ownerUserID: owner).refusals == [.item(title: "Ice skating")])

        visits.clearError()
        await visits.refusalsShown()
        #expect(await cache.state(ownerUserID: owner).refusals.isEmpty)
        #expect(visits.error == nil)
    }

    @Test func theHiddenQuestionComesBackOnTheThirtiethDayAcrossTheClockChange() async throws {
        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        let cache = InMemoryVisitsCache()
        let visits = model(cache)
        await visits.configure(ownerUserID: owner)
        // 23:30 on 10 October. Summer time ends on 25 October.
        let lateEvening = try #require(ISO8601DateFormatter().date(from: "2026-10-10T21:30:00Z"))

        await visits.hidePrompt(now: lateEvening, calendar: oslo)

        #expect(visits.homeCard(on: LockScreenCalendarDate(year: 2_026, month: 11, day: 8)) == .hidden)
        #expect(visits.homeCard(on: LockScreenCalendarDate(year: 2_026, month: 11, day: 9)) == .prompt)
        let returnDay = await cache.state(ownerUserID: owner).promptReturnDay
        #expect(returnDay == LockScreenCalendarDate(year: 2_026, month: 11, day: 9))
    }
}
