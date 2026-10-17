import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

struct PostPairingPlanTests {
    @Test func joinedPartnerGetsEveryStepInOrder() {
        let facts = PostPairingFacts(
            hasGift: true,
            startedOn: "2024-03-03",
            acceptedInvite: true,
            questionTimeIsOn: false,
            partnerAnswersWaiting: true
        )

        #expect(PostPairingPlan.steps(for: facts, finished: []) == [.gift, .date, .questionTime, .answerInvite])
    }

    @Test func inviterWhoSetEverythingUpSkipsEveryStep() {
        let facts = PostPairingFacts(startedOn: "2024-03-03", acceptedInvite: false, questionTimeIsOn: true)

        #expect(PostPairingPlan.steps(for: facts, finished: []).isEmpty)
    }

    @Test func anyoneWithoutADateIsAskedForIt() {
        let facts = PostPairingFacts(startedOn: nil, acceptedInvite: false, questionTimeIsOn: true)

        #expect(PostPairingPlan.steps(for: facts, finished: []) == [.date])
    }

    @Test func questionTimeThatDidNotLoadIsSkipped() {
        let facts = PostPairingFacts(startedOn: "2024-03-03", questionTimeIsOn: nil)

        #expect(!PostPairingPlan.steps(for: facts, finished: []).contains(.questionTime))
    }

    @Test func finishedStepsNeverComeBack() {
        let facts = PostPairingFacts(
            hasGift: true,
            startedOn: "2024-03-03",
            acceptedInvite: true,
            questionTimeIsOn: false,
            partnerAnswersWaiting: true
        )

        #expect(PostPairingPlan.steps(for: facts, finished: [.gift, .date]) == [.questionTime, .answerInvite])
    }
}

@MainActor
struct PostPairingCelebrationStateTests {
    private let pairID = UUID()

    @Test func acceptedInviteStartsFirstDay() throws {
        let store = TestPairingCelebrationStore()
        var state = RootPairingCelebrationState(store: store)

        state.presentAcceptedInvite()
        state.dismiss(currentResolution: .paired(pairID: pairID))

        #expect(!state.isPresented)
        #expect(state.isFirstDayPresented)
        let progress = try #require(store.postPairingProgress(forPairID: pairID))
        #expect(!progress.isFinished)
    }

    @Test func celebrationOnLaunchStartsFirstDay() {
        let store = TestPairingCelebrationStore()
        var state = RootPairingCelebrationState(store: store)

        state.update(for: .paired(pairID: pairID))
        #expect(state.isPresented)
        state.dismiss(currentResolution: .paired(pairID: pairID))

        #expect(state.isFirstDayPresented)
        #expect(store.postPairingProgress(forPairID: pairID) != nil)
    }

    @Test func dismissedBeforeThePairIsKnownStartsProgressWhenItArrives() {
        let store = TestPairingCelebrationStore()
        var state = RootPairingCelebrationState(store: store)

        state.presentAcceptedInvite()
        state.dismiss(currentResolution: nil)
        #expect(state.isFirstDayPresented)

        state.update(for: .paired(pairID: pairID))

        #expect(state.isFirstDayPresented)
        #expect(store.hasSeenCelebration(forPairID: pairID))
        #expect(store.postPairingProgress(forPairID: pairID) != nil)
    }

    @Test func unfinishedFirstDayResumesOnTheNextLaunch() {
        let store = TestPairingCelebrationStore(seenPairIDs: [pairID])
        store.savePostPairingProgress(PostPairingProgress(), forPairID: pairID)
        var state = RootPairingCelebrationState(store: store)

        state.update(for: .paired(pairID: pairID))

        #expect(!state.isPresented)
        #expect(state.isFirstDayPresented)
    }

    @Test func finishedFirstDayNeverShowsAgain() throws {
        let store = TestPairingCelebrationStore(seenPairIDs: [pairID])
        store.savePostPairingProgress(PostPairingProgress(), forPairID: pairID)
        var state = RootPairingCelebrationState(store: store)
        state.update(for: .paired(pairID: pairID))

        state.finishFirstDay(currentResolution: .paired(pairID: pairID))
        #expect(!state.isFirstDayPresented)
        #expect(try #require(store.postPairingProgress(forPairID: pairID)).isFinished)

        var relaunched = RootPairingCelebrationState(store: store)
        relaunched.update(for: .paired(pairID: pairID))
        #expect(!relaunched.isFirstDayPresented)
    }

    @Test func pairCelebratedWithoutFirstDayProgressShowsNothing() {
        var state = RootPairingCelebrationState(store: TestPairingCelebrationStore(seenPairIDs: [pairID]))

        state.update(for: .paired(pairID: pairID))

        #expect(!state.isPresented)
        #expect(!state.isFirstDayPresented)
    }
}

@MainActor
struct PostPairingFlowModelTests {
    private let context = PostPairingContext(
        pairID: UUID(),
        currentUserID: UUID(),
        partnerUserID: UUID(),
        coupleID: UUID()
    )

    private func makeModel(
        store: TestPairingCelebrationStore,
        loader: PostPairingFakeLoader,
        loadTimeout: Duration = .seconds(5)
    ) -> PostPairingFlowModel {
        PostPairingFlowModel(
            store: store,
            loader: loader,
            widgetConfigurations: PostPairingNoWidgets(),
            loadTimeout: loadTimeout
        )
    }

    @Test func joinedPartnerStartsWithTheGift() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(store: store, loader: PostPairingFakeLoader(gift: .ready(.sample)))

        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        #expect(model.screen == .gift)
        #expect(model.gift != nil)
        #expect(model.acceptedInvite)
    }

    /// Who joined comes from the server, so a reinstall that lost this phone's
    /// progress still confirms the partner's date.
    @Test func joinedPartnerWithoutProgressOnThisPhoneConfirmsTheDate() async {
        let model = makeModel(store: TestPairingCelebrationStore(), loader: PostPairingFakeLoader())

        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        #expect(model.screen == .date)
    }

    @Test func anOpenedGiftIsSavedAndSkippedAfterARestart() async throws {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(store: store, loader: PostPairingFakeLoader(gift: .ready(.sample)))
        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        model.giftOpened()
        #expect(try #require(store.postPairingProgress(forPairID: context.pairID)).finishedSteps == [.gift])

        let restarted = makeModel(store: store, loader: PostPairingFakeLoader(gift: .ready(.sample)))
        restarted.prepare(context)
        await restarted.start(startedOn: "2024-03-03", acceptedInvite: true)
        #expect(restarted.screen == .date)
    }

    @Test func aGiftThatIsTooSlowIsSkipped() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(
            store: store,
            loader: PostPairingFakeLoader(gift: .ready(.sample), giftDelay: .seconds(2)),
            loadTimeout: .milliseconds(50)
        )

        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        #expect(model.screen == .date)
    }

    @Test func aSlowGiftDoesNotSkipTheStepsThatLoaded() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(
            store: store,
            loader: PostPairingFakeLoader(
                gift: .ready(.sample),
                giftDelay: .seconds(2),
                questionTimeIsOn: false,
                partnerAnswersWaiting: true
            ),
            loadTimeout: .milliseconds(200)
        )

        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        #expect(model.screen == .date)
        model.dateFinished()
        #expect(model.screen == .questionTime)
        model.questionTimeFinished()
        #expect(model.screen == .answerInvite)
    }

    @Test func aGiftThatFailedToDownloadIsSkippedWithItsFailure() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(store: store, loader: PostPairingFakeLoader(gift: .failed(.offline)))

        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        #expect(model.screen == .date)
        #expect(model.giftFailure == .offline)
    }

    @Test func inviterWithNothingLeftEndsOnHomeAtOnce() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(store: store, loader: PostPairingFakeLoader(questionTimeIsOn: true))

        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: false)

        #expect(model.screen == nil)
        #expect(model.outcome == .home)
    }

    @Test func steppingThroughEndsOnTheAnswerFlow() async throws {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = makeModel(
            store: store,
            loader: PostPairingFakeLoader(questionTimeIsOn: false, partnerAnswersWaiting: true)
        )
        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)

        #expect(model.screen == .date)
        model.dateFinished()
        #expect(model.screen == .questionTime)
        model.questionTimeFinished()
        #expect(model.screen == .answerInvite)
        model.answerInviteFinished(answerNow: true)

        #expect(model.outcome == .answerQuestions)
        let progress = try #require(store.postPairingProgress(forPairID: context.pairID))
        #expect(progress.finishedSteps == [.date, .questionTime, .answerInvite])
    }

    /// The inviter finished their first answers after the partner's sequence planned its
    /// steps. The last step still leads to the answer invite.
    @Test func answersThatArriveDuringTheSequenceStillGetTheInvite() async {
        let store = TestPairingCelebrationStore()
        let model = makeModel(
            store: store,
            loader: PostPairingFakeLoader(questionTimeIsOn: false, answersWaitingAfterFirstCheck: true)
        )
        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: false)
        #expect(model.screen == .questionTime)

        model.questionTimeFinished()
        for _ in 0 ..< 100 where model.screen != .answerInvite {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.screen == .answerInvite)
        #expect(model.outcome == nil)
    }

    @Test func noLateAnswersEndsOnHome() async {
        let model = makeModel(
            store: TestPairingCelebrationStore(),
            loader: PostPairingFakeLoader(questionTimeIsOn: false)
        )
        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: false)

        model.questionTimeFinished()
        for _ in 0 ..< 100 where model.outcome == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.outcome == .home)
    }

    @Test func closingTheDrawingWithoutSendingMovesOn() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = PostPairingFlowModel(
            store: store,
            loader: PostPairingFakeLoader(gift: .ready(.sample)),
            widgetConfigurations: PostPairingNoWidgets(),
            drawingViewModel: WidgetDrawingViewModel(
                service: WidgetCanvasServiceSpy(),
                uploader: WidgetCanvasUploadSpy(),
                draftStore: InMemoryWidgetDrawingDraftStore()
            )
        )
        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)
        model.giftOpened()

        model.drawBack(authorName: "Alex")
        #expect(model.drawingViewModel != nil)
        model.drawingClosed()

        #expect(model.drawingViewModel == nil)
        #expect(model.screen == .date)
    }

    /// The next step goes in before the drawing screen closes, and the close that
    /// follows a send doesn't skip a second step.
    @Test func sendingTheDrawingMovesOnOnce() async {
        let store = TestPairingCelebrationStore()
        store.savePostPairingProgress(PostPairingProgress(), forPairID: context.pairID)
        let model = PostPairingFlowModel(
            store: store,
            loader: PostPairingFakeLoader(gift: .ready(.sample)),
            widgetConfigurations: PostPairingNoWidgets(),
            drawingViewModel: WidgetDrawingViewModel(
                service: WidgetCanvasServiceSpy(),
                uploader: WidgetCanvasUploadSpy(),
                draftStore: InMemoryWidgetDrawingDraftStore()
            )
        )
        model.prepare(context)
        await model.start(startedOn: "2024-03-03", acceptedInvite: true)
        model.giftOpened()
        model.drawBack(authorName: "Alex")

        await model.drawingSent()
        model.drawingClosed()

        #expect(model.drawingViewModel == nil)
        #expect(model.screen == .date)
    }
}

struct PostPairingProgressStoreTests {
    @MainActor
    @Test func progressRoundTripsAndClearsWithTheCelebration() throws {
        let suiteName = "PaeoniaAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPairingCelebrationStore(defaults: defaults)
        let pairID = UUID()
        let progress = PostPairingProgress(finishedSteps: [.gift, .date], isFinished: false)

        store.savePostPairingProgress(progress, forPairID: pairID)
        #expect(store.postPairingProgress(forPairID: pairID) == progress)

        store.clearAll()
        #expect(store.postPairingProgress(forPairID: pairID) == nil)
    }
}

// MARK: - Fakes

private extension AccessRouteResolution {
    static func paired(pairID: UUID) -> AccessRouteResolution {
        AccessRouteResolution(
            route: .paired,
            snapshot: AccessRouteSnapshot(
                userEntitlement: nil,
                coupleEntitlement: nil,
                relationshipState: RemoteRelationshipState(
                    coupleID: UUID(),
                    pairID: pairID,
                    relationshipStatus: .active,
                    memberStatus: .active,
                    acceptedInvite: false,
                    partnerUserID: UUID(),
                    partnerDisplayName: "Robin",
                    partnerProfilePhotoAssetID: nil,
                    startedOn: "2024-03-03",
                    endedAt: nil,
                    deleteAfter: nil,
                    endedNoticeSeenAt: nil
                ),
                hasPendingInvite: false
            )
        )
    }
}

private extension PostPairingGift {
    static let sample = PostPairingGift(revisionID: UUID(), drawing: PKDrawing())
}

private struct PostPairingFakeLoader: PostPairingDataLoading {
    var gift: PostPairingGiftLoad = .none
    var giftDelay: Duration = .zero
    var questionTimeIsOn: Bool? = true
    var partnerAnswersWaiting = false
    /// The partner's answers land after the first load.
    var answersWaitingAfterFirstCheck = false
    let answerChecks = PostPairingCallCounter()

    func partnerGift(partnerUserID _: UUID) async -> PostPairingGiftLoad {
        try? await Task.sleep(for: giftDelay)
        return gift
    }

    // swiftlint:disable async_without_await
    func questionTimeIsOn() async -> Bool? {
        questionTimeIsOn
    }

    func partnerAnswersWaiting(currentUserID _: UUID) async -> Bool {
        let call = await answerChecks.next()
        return partnerAnswersWaiting || (answersWaitingAfterFirstCheck && call > 1)
    }

    // swiftlint:enable async_without_await
}

private actor PostPairingCallCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

private struct PostPairingNoWidgets: WidgetConfigurationProviding {
    // swiftlint:disable:next async_without_await
    func installedWidgetKinds() async throws -> [String] { [] }
}
