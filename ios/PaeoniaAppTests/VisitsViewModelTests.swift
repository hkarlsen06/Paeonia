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
        #expect(visits.error == .refused(items: ["Ice skating"], visits: []))
        #expect(visits.itemDraft == "Ice skating")
    }

    @Test func aRefusalStaysOnThePhoneUntilThePersonDismissesItsMessage() async {
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        let visits = model(cache)
        await visits.setActive(true)
        await visits.configure(ownerUserID: owner)

        #expect(visits.error == .refused(items: ["Ice skating"], visits: []))

        // The banner is on screen. Another reload neither repeats it nor forgets the refusal.
        visits.clearError()
        await visits.reload()
        #expect(visits.error == nil)
        #expect(await cache.state(ownerUserID: owner).refusals == [.item(title: "Ice skating")])

        await visits.refusalBannerDismissed()
        #expect(await cache.state(ownerUserID: owner).refusals.isEmpty)
        #expect(visits.error == nil)
    }

    @Test func aLaterRefusalsMessageAlsoNamesTheOnesStillOnScreen() async {
        let first = Visit(id: UUID(), startDate: "2026-11-25", endDate: "2026-11-28", place: nil)
        let second = Visit(id: UUID(), startDate: "2026-12-03", endDate: "2026-12-05", place: nil)
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.visit(first), ownerUserID: owner)
        let visits = model(cache)
        await visits.setActive(true)
        await visits.configure(ownerUserID: owner)
        #expect(visits.error == .refused(items: [], visits: [first]))
        visits.clearError()

        // The next queued write is refused while the first banner is still on screen. Its
        // banner takes the first one's place, so it has to name both.
        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        await cache.recordRefusal(.visit(second), ownerUserID: owner)
        await visits.reload()

        #expect(visits.error == .refused(items: ["Ice skating"], visits: [first, second]))
        #expect(await cache.state(ownerUserID: owner).refusals.count == 3)

        visits.clearError()
        await visits.refusalBannerDismissed()
        #expect(await cache.state(ownerUserID: owner).refusals.isEmpty)
        #expect(visits.error == nil)
    }

    @Test func refusalsComeBackWhenAnotherBannerTookTheirBannersPlace() async {
        let visit = Visit(id: UUID(), startDate: "2026-11-25", endDate: "2026-11-28", place: nil)
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.visit(visit), ownerUserID: owner)
        let visits = model(cache)
        await visits.setActive(true)
        await visits.configure(ownerUserID: owner)
        visits.clearError()

        visits.refusalBannerReplaced()
        await visits.reload()

        #expect(visits.error == .refused(items: [], visits: [visit]))
        #expect(await cache.state(ownerUserID: owner).refusals == [.visit(visit)])
    }

    @Test func theListScreenNamesRefusedItemsAndTheBannerNamesRefusedVisits() async {
        let visit = Visit(id: UUID(), startDate: "2026-11-25", endDate: "2026-11-28", place: nil)
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        await cache.recordRefusal(.visit(visit), ownerUserID: owner)
        let visits = model(cache)
        visits.isListShown = true
        await visits.setActive(true)
        await visits.configure(ownerUserID: owner)

        #expect(visits.listError == .refused(items: ["Ice skating"], visits: []))
        #expect(visits.error == .refused(items: [], visits: [visit]))

        // Each message takes only its own refusals with it.
        visits.clearError()
        await visits.clearListError()
        #expect(visits.listError == nil)
        #expect(await cache.state(ownerUserID: owner).refusals == [.visit(visit)])

        await visits.refusalBannerDismissed()
        #expect(await cache.state(ownerUserID: owner).refusals.isEmpty)
    }

    @Test func addingARefusedItemAgainAnswersItsMessage() async {
        let cache = InMemoryVisitsCache()
        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        let visits = model(cache)
        visits.isListShown = true
        await visits.setActive(true)
        await visits.configure(ownerUserID: owner)
        #expect(visits.itemDraft == "Ice skating")

        // The person taps Add without typing, and the server refuses the item once more.
        #expect(await visits.addItem())
        #expect(visits.listError == nil)
        #expect(await cache.state(ownerUserID: owner).refusals.isEmpty)

        await cache.recordRefusal(.item(title: "Ice skating"), ownerUserID: owner)
        await visits.reload()
        #expect(visits.listError == .refused(items: ["Ice skating"], visits: []))
    }

    @Test func movingTheFirstDayKeepsTheLastDayWithinTheDaysTheServerAccepts() throws {
        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(LockScreenCalendarDate(year: year, month: month, day: day).startOfDay(in: oslo))
        }

        func end(_ end: Date, from oldStart: Date, to newStart: Date) -> Date {
            Visit.end(end, afterStartMovedFrom: oldStart, to: newStart, calendar: oslo)
        }

        let kept = try end(day(2_026, 11, 28), from: day(2_026, 11, 25), to: day(2_026, 12, 1))
        #expect(kept == (try day(2_026, 12, 4)))

        let late = try end(day(2_026, 11, 28), from: day(2_026, 11, 25), to: day(2_100, 12, 31))
        #expect(late == (try day(2_100, 12, 31)))

        let early = try end(day(2_000, 1, 3), from: day(2_000, 1, 5), to: day(2_000, 1, 1))
        #expect(early == (try day(2_000, 1, 1)))
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

        let lastHiddenNoon = try #require(ISO8601DateFormatter().date(from: "2026-11-08T11:00:00Z"))
        let returnNoon = try #require(ISO8601DateFormatter().date(from: "2026-11-09T11:00:00Z"))
        #expect(visits.homeCard(at: lastHiddenNoon, streak: .hidden, calendar: oslo) == .hidden)
        #expect(visits.homeCard(at: returnNoon, streak: .hidden, calendar: oslo) == .prompt)
        let returnDay = await cache.state(ownerUserID: owner).promptReturnDay
        #expect(returnDay == LockScreenCalendarDate(year: 2_026, month: 11, day: 9))
    }
}
