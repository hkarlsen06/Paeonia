import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct LookBackViewModelTests {
    private struct Setup {
        let model: LookBackViewModel
        let service: StubLookBackService
        let cache: MemoryLookBackCache
    }

    private func makeModel(
        _ results: [Result<LookBackResponse, Error>],
        cache: MemoryLookBackCache = MemoryLookBackCache()
    ) -> Setup {
        let service = StubLookBackService(results)
        return Setup(model: LookBackViewModel(service: service, cache: cache), service: service, cache: cache)
    }

    @Test func showsTheServerItemAndSavesIt() async {
        let setup = makeModel([.success(lookBackResponse(lookBackMemoryItem()))])
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: LookBackIDs.couple)
        #expect(model.item == lookBackMemoryItem())
        let saved = setup.cache.load(ownerUserID: LookBackIDs.user, coupleID: LookBackIDs.couple)
        #expect(saved == LookBackCacheEntry(coupleID: LookBackIDs.couple, item: lookBackMemoryItem()))
    }

    @Test func readsAgainWhenTheCouplesDayEnds() async {
        let endsAt = Date(timeIntervalSince1970: 1_800_003_600)
        let setup = makeModel([.success(lookBackResponse(lookBackMemoryItem(), endsAt: endsAt))])
        await setup.model.configure(userID: LookBackIDs.user, coupleID: nil)
        #expect(setup.model.refreshAt == endsAt)
    }

    @Test func aFailedReadKeepsWhatTheCacheShowed() async {
        let cache = MemoryLookBackCache()
        cache.save(
            LookBackCacheEntry(coupleID: LookBackIDs.couple, item: lookBackMemoryItem()),
            ownerUserID: LookBackIDs.user
        )
        let setup = makeModel([.failure(LookBackStubFailure())], cache: cache)
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: LookBackIDs.couple)
        #expect(model.item == lookBackMemoryItem())
    }

    @Test func aFailedLaterReadKeepsTheCurrentItem() async {
        let setup = makeModel([.success(lookBackResponse(lookBackMemoryItem())), .failure(LookBackStubFailure())])
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        await model.refresh()
        #expect(model.item == lookBackMemoryItem())
    }

    @Test func anEmptyResultHidesTheCardAndIsSaved() async {
        let cache = MemoryLookBackCache()
        cache.save(LookBackCacheEntry(coupleID: nil, item: lookBackMemoryItem()), ownerUserID: LookBackIDs.user)
        let setup = makeModel([.success(lookBackResponse(nil))], cache: cache)
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        #expect(model.item == nil)
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: nil)?.item == nil)
    }

    @Test func aNewDayShowsTheNewItem() async {
        let setup = makeModel([
            .success(lookBackResponse(lookBackMemoryItem(title: "Old"))),
            .success(lookBackResponse(lookBackMemoryItem(title: "New"))),
        ])
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        await model.refresh()
        #expect(model.item?.memory?.title == "New")
    }

    @Test func configuringTheSameUserAgainReadsAgain() async {
        let setup = makeModel([
            .success(lookBackResponse(lookBackMemoryItem(title: "Old"))),
            .success(lookBackResponse(lookBackMemoryItem(title: "New"))),
        ])
        await setup.model.configure(userID: LookBackIDs.user, coupleID: nil)
        await setup.model.configure(userID: LookBackIDs.user, coupleID: nil)
        #expect(setup.model.item?.memory?.title == "New")
    }

    @Test func aDifferentUserStartsClean() async {
        let cache = MemoryLookBackCache()
        let setup = makeModel(
            [.success(lookBackResponse(lookBackMemoryItem())), .failure(LookBackStubFailure())],
            cache: cache
        )
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        #expect(model.item == lookBackMemoryItem())
        await model.configure(userID: LookBackIDs.otherUser, coupleID: nil)
        #expect(model.item == nil)
        await model.configure(userID: nil, coupleID: nil)
        #expect(model.item == nil)
    }

    @Test func doesNotReadWithoutAUser() async {
        let setup = makeModel([.success(lookBackResponse(lookBackMemoryItem()))])
        await setup.model.refresh()
        #expect(setup.model.item == nil)
        #expect(setup.service.requestTimes.isEmpty)
    }

    @Test func aCardSavedForAnotherCoupleGoesAwayAndAskForARead() async {
        let cache = MemoryLookBackCache()
        cache.save(
            LookBackCacheEntry(coupleID: LookBackIDs.couple, item: lookBackMemoryItem()),
            ownerUserID: LookBackIDs.user
        )
        let setup = makeModel([.failure(LookBackStubFailure())], cache: cache)
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        #expect(model.item == lookBackMemoryItem())
        let before = model.refreshRequest
        model.updateCouple(LookBackIDs.otherCouple)
        #expect(model.item == nil)
        #expect(model.refreshRequest == before + 1)
    }

    @Test func theRequestTimeIsRoundedDownToAQuarterOfAnHour() async {
        // 2026-10-14 12:22:30 UTC.
        let date = Date(timeIntervalSince1970: 1_791_980_550)
        #expect(LookBackViewModel.requestTime(date) == Date(timeIntervalSince1970: 1_791_980_100))
        let setup = makeModel([.success(lookBackResponse(nil))])
        await setup.model.configure(userID: LookBackIDs.user, coupleID: nil)
        let asked = setup.service.requestTimes.first?.timeIntervalSince1970 ?? 1
        #expect(asked.truncatingRemainder(dividingBy: 900) == 0)
    }

    @Test func aReadThatLandsAfterAPrivacyPurgeShowsAndSavesNothing() async {
        let service = GatedLookBackService()
        let cache = MemoryLookBackCache()
        let model = LookBackViewModel(service: service, cache: cache)
        let read = Task { await model.configure(userID: LookBackIDs.user, coupleID: nil) }
        await lookBackWaitUntil { service.startedCount == 1 }
        cache.clearAll()
        service.finish(read: 0, with: lookBackResponse(lookBackMemoryItem()))
        await read.value
        #expect(model.item == nil)
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: nil) == nil)
    }

    @Test func aCancelledReadShowsAndSavesNothing() async {
        let service = GatedLookBackService()
        let cache = MemoryLookBackCache()
        let model = LookBackViewModel(service: service, cache: cache)
        let read = Task { await model.configure(userID: LookBackIDs.user, coupleID: nil) }
        await lookBackWaitUntil { service.startedCount == 1 }
        read.cancel()
        service.finish(read: 0, with: lookBackResponse(lookBackMemoryItem()))
        await read.value
        #expect(model.item == nil)
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: nil) == nil)
    }

    @Test func anOlderReadFinishingLastDoesNotReplaceANewerOne() async {
        let service = GatedLookBackService()
        let model = LookBackViewModel(service: service, cache: MemoryLookBackCache())
        let older = Task { await model.configure(userID: LookBackIDs.user, coupleID: nil) }
        await lookBackWaitUntil { service.startedCount == 1 }
        let newer = Task { await model.refresh() }
        await lookBackWaitUntil { service.startedCount == 2 }
        service.finish(read: 1, with: lookBackResponse(lookBackMemoryItem(title: "New")))
        await newer.value
        service.finish(read: 0, with: lookBackResponse(lookBackMemoryItem(title: "Old")))
        await older.value
        #expect(model.item?.memory?.title == "New")
    }

    @Test func aChangeToTheShownMemoryReadsAgainAndDropsItWhenItIsGone() async {
        let setup = makeModel([.success(lookBackResponse(lookBackMemoryItem())), .success(lookBackResponse(nil))])
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        #expect(model.item == lookBackMemoryItem())
        let observing = Task { await model.observeStoreChanges() }
        // Let the observer subscribe before the change is posted.
        try? await Task.sleep(for: .milliseconds(50))
        LocalStoreChanges.post(.memories, ownerUserID: LookBackIDs.user)
        await lookBackWaitUntil { model.item == nil }
        observing.cancel()
        #expect(model.item == nil)
        #expect(setup.cache.load(ownerUserID: LookBackIDs.user, coupleID: nil)?.item == nil)
    }

    @Test func aChangeToOtherContentDoesNotReadAgain() async {
        let setup = makeModel([.success(lookBackResponse(lookBackMemoryItem())), .success(lookBackResponse(nil))])
        let model = setup.model
        await model.configure(userID: LookBackIDs.user, coupleID: nil)
        let observing = Task { await model.observeStoreChanges() }
        try? await Task.sleep(for: .milliseconds(50))
        LocalStoreChanges.post(.dailyChallenge, ownerUserID: LookBackIDs.user)
        LocalStoreChanges.post(.memories, ownerUserID: LookBackIDs.otherUser)
        try? await Task.sleep(for: .milliseconds(100))
        observing.cancel()
        #expect(model.item == lookBackMemoryItem())
        #expect(setup.service.requestTimes.count == 1)
    }
}
