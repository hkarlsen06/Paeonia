import Observation
import PencilKit
import UIKit

/// Who the first day sequence loads for. The names and the start date are only
/// shown, so they reach the views without restarting the loads.
nonisolated struct PostPairingContext: Equatable, Sendable {
    let pairID: UUID
    let currentUserID: UUID
    let partnerUserID: UUID
    let coupleID: UUID
}

/// How the sequence ended.
enum PostPairingOutcome: Equatable {
    case home
    /// "Answer now" on the answer invitation.
    case answerQuestions
}

/// Runs the first day sequence between the pairing celebration and the tabs.
///
/// `prepare` starts loading while the celebration still plays: the partner's widget
/// drawing, the question time setting, and today's questions. `start` then decides
/// the steps from what loaded (`PostPairingPlan`) and from this phone's progress for
/// the pair, so a step the person already moved past never comes back. A load that
/// fails or takes too long only skips its own step.
@MainActor
@Observable
final class PostPairingFlowModel {
    enum Screen: Equatable {
        case gift
        /// After a drawing back, for someone without the widget.
        case widgetNudge
        case date
        case questionTime
        case answerInvite
    }

    private(set) var screen: Screen?
    /// The partner's drawing, set once it has loaded.
    private(set) var gift: PostPairingGiftModel?
    /// The drawing screen opened from the gift, while it is open.
    private(set) var drawingViewModel: WidgetDrawingViewModel?
    /// The drawing this person sent back, for the widget nudge.
    private(set) var drawnBackImage: UIImage?
    /// The partner's drawing did not load. The view shows the banner and clears it.
    private(set) var giftFailure: PaeoniaFailure?
    private(set) var outcome: PostPairingOutcome?

    /// This person joined with the partner's code, so the date step confirms the
    /// partner's date.
    var acceptedInvite: Bool {
        facts.acceptedInvite
    }

    private(set) var context: PostPairingContext?
    @ObservationIgnored private let store: any PairingCelebrationStoring
    @ObservationIgnored private let loader: any PostPairingDataLoading
    @ObservationIgnored private let widgetConfigurations: any WidgetConfigurationProviding
    @ObservationIgnored private let loadTimeout: Duration
    @ObservationIgnored private let questionTimeModel: QuestionTimeModel?
    @ObservationIgnored private let milestoneViewModel: RelationshipMilestoneViewModel?
    @ObservationIgnored private let injectedDrawingViewModel: WidgetDrawingViewModel?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var facts = PostPairingFacts()
    @ObservationIgnored private var pendingGiftFailure: PaeoniaFailure?
    @ObservationIgnored private var queue: [PostPairingStep] = []
    @ObservationIgnored private var hasStarted = false
    /// Every load for the current context has settled.
    @ObservationIgnored private var isLoaded = false

    init(
        store: any PairingCelebrationStoring,
        loader: any PostPairingDataLoading = LivePostPairingDataLoader(),
        widgetConfigurations: any WidgetConfigurationProviding = WidgetCenterConfigurations(),
        loadTimeout: Duration = .seconds(2),
        questionTimeModel: QuestionTimeModel? = nil,
        milestoneViewModel: RelationshipMilestoneViewModel? = nil,
        drawingViewModel: WidgetDrawingViewModel? = nil
    ) {
        self.store = store
        self.loader = loader
        self.widgetConfigurations = widgetConfigurations
        self.loadTimeout = loadTimeout
        self.questionTimeModel = questionTimeModel
        self.milestoneViewModel = milestoneViewModel
        injectedDrawingViewModel = drawingViewModel
    }

    /// The question time step's model. Developer scenarios inject a local one.
    func makeQuestionTimeModel() -> QuestionTimeModel {
        questionTimeModel ?? QuestionTimeModel()
    }

    /// The date step's view model. Developer scenarios inject a local one.
    func makeMilestoneViewModel() -> RelationshipMilestoneViewModel {
        milestoneViewModel ?? RelationshipMilestoneViewModel()
    }

    // MARK: Loading

    /// Starts over and loads for `context`. The same context again does nothing,
    /// so the last step stays on screen while the root animates it away.
    func prepare(_ context: PostPairingContext) {
        guard context != self.context else {
            return
        }
        reset()
        self.context = context
        loadTask = Task { [weak self] in
            await self?.load(context)
        }
    }

    /// Forgets everything, for when the paired screen goes away (sign-out or
    /// unpair). The same pair can then start over.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        gift?.stop()
        context = nil
        screen = nil
        gift = nil
        drawingViewModel = nil
        drawnBackImage = nil
        giftFailure = nil
        outcome = nil
        facts = PostPairingFacts()
        pendingGiftFailure = nil
        queue = []
        hasStarted = false
        isLoaded = false
    }

    /// Each load publishes its result as soon as it settles, so a slow one doesn't hold
    /// back the steps of the others when `start` stops waiting.
    private func load(_ context: PostPairingContext) async {
        async let giftLoaded: Void = loadGift(context)
        async let questionTimeLoaded: Void = loadQuestionTime(context)
        async let answersLoaded: Void = loadAnswersWaiting(context)
        _ = await (giftLoaded, questionTimeLoaded, answersLoaded)
        guard isCurrent(context) else {
            return
        }
        isLoaded = true
    }

    private func loadQuestionTime(_ context: PostPairingContext) async {
        let isOn = await loader.questionTimeIsOn()
        guard isCurrent(context) else {
            return
        }
        facts.questionTimeIsOn = isOn
    }

    private func loadAnswersWaiting(_ context: PostPairingContext) async {
        let isWaiting = await loader.partnerAnswersWaiting(currentUserID: context.currentUserID)
        guard isCurrent(context) else {
            return
        }
        facts.partnerAnswersWaiting = isWaiting
    }

    /// The celebration names the gift as soon as it is here.
    private func loadGift(_ context: PostPairingContext) async {
        let giftLoad = await loader.partnerGift(partnerUserID: context.partnerUserID)
        guard isCurrent(context) else {
            return
        }
        switch giftLoad {
        case .none:
            break
        case let .ready(loadedGift):
            gift = PostPairingGiftModel(gift: loadedGift)
            facts.hasGift = true
        case let .failed(failure):
            pendingGiftFailure = failure
        }
    }

    private func isCurrent(_ context: PostPairingContext) -> Bool {
        !Task.isCancelled && self.context == context
    }

    // MARK: Steps

    /// Decides the steps and shows the first one, or ends the sequence when none
    /// apply. Waits up to `loadTimeout` for loads that are still running.
    func start(startedOn: String?, acceptedInvite: Bool) async {
        guard !hasStarted, let context else {
            return
        }
        await waitForLoads()
        guard !Task.isCancelled, self.context == context, !hasStarted else {
            return
        }
        hasStarted = true

        let progress = store.postPairingProgress(forPairID: context.pairID) ?? PostPairingProgress()
        facts.startedOn = startedOn
        facts.acceptedInvite = acceptedInvite
        queue = PostPairingPlan.steps(for: facts, finished: progress.finishedSteps)
        if !progress.finishedSteps.contains(.gift) {
            giftFailure = pendingGiftFailure
        }
        advance()
    }

    /// Awaiting the load task itself would outlast the timeout, since waiting on a
    /// task's value ignores cancellation, so this checks a flag instead.
    private func waitForLoads() async {
        let deadline = ContinuousClock.now + loadTimeout
        while !isLoaded, !Task.isCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func advance() {
        guard !queue.isEmpty else {
            outcome = .home
            return
        }
        screen = Self.screen(for: queue.removeFirst())
    }

    private static func screen(for step: PostPairingStep) -> Screen {
        switch step {
        case .gift: .gift
        case .date: .date
        case .questionTime: .questionTime
        case .answerInvite: .answerInvite
        }
    }

    /// Saves that the person moved past `step` for this pair.
    private func complete(_ step: PostPairingStep) {
        guard let context else {
            return
        }
        var progress = store.postPairingProgress(forPairID: context.pairID) ?? PostPairingProgress()
        progress.finishedSteps.insert(step)
        store.savePostPairingProgress(progress, forPairID: context.pairID)
    }

    func clearGiftFailure() {
        giftFailure = nil
    }

    // MARK: Gift

    /// The envelope was tapped. Saved right away, so the gift never plays twice.
    func giftOpened() {
        complete(.gift)
    }

    func giftLater() {
        complete(.gift)
        advance()
    }

    /// Opens the drawing screen.
    func drawBack(authorName: String?) {
        guard let context, drawingViewModel == nil else {
            return
        }
        drawingViewModel = injectedDrawingViewModel ?? WidgetDrawingViewModel(
            ownerUserID: context.currentUserID,
            coupleID: context.coupleID,
            authorName: authorName,
            live: WidgetLiveDrawing(coupleID: context.coupleID)
        )
    }

    /// The drawing went out, or is waiting for a connection. Shows the widget nudge
    /// with it unless the widget is already on the Home Screen. The next step goes in
    /// under the drawing screen first, so closing it lands there instead of passing
    /// the gift on the way.
    func drawingSent() async {
        guard let sent = drawingViewModel else {
            return
        }
        let image = Self.image(of: sent)
        let isInstalled = await WidgetNudgeModel.isWidgetInstalled(configurations: widgetConfigurations)
        guard drawingViewModel === sent, screen == .gift else {
            return
        }
        if let image, !isInstalled {
            drawnBackImage = image
            screen = .widgetNudge
        } else {
            advance()
        }
        try? await Task.sleep(for: .seconds(PaeoniaMotion.motionSlow))
        drawingViewModel = nil
    }

    /// The drawing screen closed without a drawing sent. A close after a send has
    /// already moved on.
    func drawingClosed() {
        guard drawingViewModel != nil else {
            return
        }
        drawingViewModel = nil
        if screen == .gift {
            advance()
        }
    }

    func widgetNudgeFinished() {
        drawnBackImage = nil
        advance()
    }

    /// The sent drawing as the widget shows it.
    private static func image(of viewModel: WidgetDrawingViewModel) -> UIImage? {
        let side = viewModel.drawingCanvasSide
            ?? viewModel.laidOutCanvasSide
            ?? WidgetDrawingViewModel.fallbackCanvasSide
        guard side > 0, !viewModel.drawing.strokes.isEmpty else {
            return nil
        }
        var image: UIImage?
        // Light, like the widget's own previews, so the ink colors match.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = viewModel.drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 2)
        }
        return image
    }

    // MARK: Other steps

    func dateFinished() {
        complete(.date)
        advance()
    }

    func questionTimeFinished() {
        complete(.questionTime)
        advance()
    }

    func answerInviteFinished(answerNow: Bool) {
        complete(.answerInvite)
        outcome = answerNow ? .answerQuestions : .home
    }
}
