import SwiftUI

/// One visit to the app, from a cold launch or a return from the background, as far as
/// opening today's question by itself goes.
nonisolated enum TodaysQuestionVisit: Equatable {
    /// Waiting for the app to be in front, past the launch screen and unlocked.
    case starting
    /// In front, past the launch screen and unlocked since `since`.
    case ready(since: ContinuousClock.Instant)
    /// Today's question opened by itself and is still up.
    case opened
    /// Nothing more happens until the next visit. The question opened and closed, the
    /// visit came with a destination, the person was elsewhere, or the time to decide ran out.
    case decided

    /// Whether a destination that arrives now (a push, widget, link, Siri or Spotlight)
    /// closes the question this visit opened by itself. It wins over that question, unless
    /// it leads to today's question too. Either way the visit is decided.
    func destinationClosesQuestion(opensTodaysQuestion: Bool) -> Bool {
        self == .opened && !opensTodaysQuestion
    }
}

/// What decides whether today's question opens by itself right now.
nonisolated struct TodaysQuestionCheck: Equatable {
    /// Today's question can open: its couple day, and whether the partner has answered.
    struct Openable: Equatable {
        let day: String
        let partnerHasAnswered: Bool
    }

    enum Action: Equatable {
        case none
        case startWindow
        case decide
        /// Wait for the card or the day to change, and decide at `deadline` if neither does.
        case wait(until: ContinuousClock.Instant)
        /// The first opening of the couple day. It opens at once in place of the screen, so
        /// the question is the first thing the person sees.
        case openInPlace
        /// The partner answered since it opened today. Only the server knows that, so it
        /// can come after the person sees Home, and the question zooms out of Home's card.
        case openWithZoom
    }

    /// The question opens within this time of the app being ready, or not at all, so a
    /// slow load never interrupts someone already using the app.
    static let window: Duration = .seconds(4)

    let visit: TodaysQuestionVisit
    /// In front, past the launch screen, and unlocked.
    let isAppReady: Bool
    /// The launch intro, Home's map flight included, has ended, so Home's card is at rest
    /// for a zoom.
    let isIntroComplete: Bool
    /// Home is in front, with nothing presented over it.
    let isHomeInFront: Bool
    /// Nil while the card loads, after the user answered, or while it still shows a day
    /// that has ended.
    let openable: Openable?

    func action(lastOpening: TodaysQuestionOpening?, now: ContinuousClock.Instant) -> Action {
        switch visit {
        case .opened, .decided:
            return .none
        case .starting:
            return isAppReady ? .startWindow : .none
        case let .ready(since):
            guard isAppReady else { return .none }
            guard isHomeInFront else { return .decide }
            let deadline = since + Self.window
            guard now < deadline else { return .decide }
            return openingAction(lastOpening: lastOpening) ?? .wait(until: deadline)
        }
    }

    /// How the question opens now, or nil while it waits for the card or the partner.
    private func openingAction(lastOpening: TodaysQuestionOpening?) -> Action? {
        guard let openable else { return nil }
        switch TodaysQuestionOpening.occasion(
            on: openable.day, partnerHasAnswered: openable.partnerHasAnswered, after: lastOpening
        ) {
        case .firstOfDay:
            return .openInPlace
        case .partnerAnswered where isIntroComplete:
            return .openWithZoom
        case .partnerAnswered, nil:
            return nil
        }
    }
}

/// Opens today's question by itself on a plain open of the app, at most once a couple
/// day, and once more when the partner has answered since. Only `RootView` gives
/// `MainTabView` a store, so developer flows and UI tests never see it.
extension MainTabView {
    func openingTodaysQuestion(on content: some View) -> some View {
        content
            // A visit starts on leaving, because a notification tap can arrive just
            // before or just after the app becomes active.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { todaysQuestionVisit = .starting }
            }
            // A push, widget, link, Siri or Spotlight brought the person somewhere.
            .onChange(of: deepLink.wrappedValue, initial: true) { _, link in
                if let link { destinationArrived(opensTodaysQuestion: link.opensTodaysQuestion) }
            }
            .onChange(of: widgetDrawingPresented.wrappedValue, initial: true) { _, isPresented in
                if isPresented { destinationArrived(opensTodaysQuestion: false) }
            }
            .onChange(of: isAnswerFlowPresented) { _, isPresented in
                if !isPresented, todaysQuestionVisit == .opened { todaysQuestionVisit = .decided }
            }
            .task(id: todaysQuestionCheck) {
                await openTodaysQuestionIfDue()
            }
    }

    /// Opening today's question by any route counts as today's opening.
    func recordTodaysQuestionOpening() {
        todaysQuestionVisit = .decided
        guard let todaysQuestionOpenings, let userID = identity.currentUserID else { return }
        todaysQuestionOpenings.record(
            TodaysQuestionOpening(
                day: todaysQuestionDay,
                partnerHadAnswered: dailyChallengeViewModel.homeCardState.hasPartnerAnsweredToday
            ),
            userID: userID
        )
    }

    /// Opens today's question at once in place of the screen, with no zoom and no wait.
    /// The flow shows its loading state until the question is there.
    func openTodaysQuestionInPlace(curtain: DailyFlowCurtain?) {
        recordTodaysQuestionOpening()
        dailyFlowSource = .us
        dailyFlowEntrance = .inPlace(curtain: curtain)
        PresentingInPlace.begin { isAnswerFlowPresented = true }
        Task { await loadQuestionOpenedInPlace() }
    }

    /// Reads today's question, or asks the server to make it, after the flow opened in
    /// place. It closes the flow when today turns out to be answered already, or when the
    /// question can't be made (an offline phone), so the flow never stays on a screen that
    /// only says it went wrong.
    private func loadQuestionOpenedInPlace() async {
        let model = dailyChallengeViewModel
        // After the first day the tabs mount with the flow, so the model may not have
        // read anything yet. It reads only once per signed-in user.
        await model.configure(participants: dailyChallengeParticipants)
        if model.homeCardState.kind != .noChallenge {
            await model.reload()
        }
        if model.homeCardState.kind == .noChallenge {
            await model.startToday()
        }
        guard isAnswerFlowPresented else { return }
        switch model.homeCardState.kind {
        case .loading, .active:
            return
        case .complete:
            break
        case .noChallenge:
            if case .startFailed = model.notice { model.dismissNotice() }
        }
        closeAnswerFlow()
    }

    private func destinationArrived(opensTodaysQuestion: Bool) {
        if todaysQuestionVisit.destinationClosesQuestion(opensTodaysQuestion: opensTodaysQuestion) {
            isAnswerFlowPresented = false
        }
        todaysQuestionVisit = .decided
    }

    private var todaysQuestionCheck: TodaysQuestionCheck {
        TodaysQuestionCheck(
            visit: todaysQuestionVisit,
            isAppReady: scenePhase == .active && launchContentRevealed && !AppLockModel.shared.isCovering,
            isIntroComplete: launchIntroComplete,
            isHomeInFront: selection.wrappedValue == .us
                && !isModalOpen
                && !widgetDrawingPresented.wrappedValue
                && dailyChatQuestion == nil,
            openable: openableTodaysQuestion
        )
    }

    private var openableTodaysQuestion: TodaysQuestionCheck.Openable? {
        let model = dailyChallengeViewModel
        let state = model.homeCardState
        switch state.kind {
        case .noChallenge:
            // The server makes the day's question when someone first opens it.
            break
        case .active:
            // After a night away the card shows yesterday's question until the day-end
            // wake-up or a refresh rolls it over.
            guard let endsAt = model.snapshot.currentDayEndsAt, endsAt > model.now() else { return nil }
        case .loading, .complete:
            return nil
        }
        return TodaysQuestionCheck.Openable(day: todaysQuestionDay, partnerHasAnswered: state.hasPartnerAnsweredToday)
    }

    /// The couple day it is now. Days end at midnight in the couple's zone.
    private var todaysQuestionDay: String {
        let model = dailyChallengeViewModel
        return MemoryTimeline.localDateString(for: model.now(), timeZone: model.snapshot.timeZone)
    }

    private func openTodaysQuestionIfDue() async {
        guard let todaysQuestionOpenings, let userID = identity.currentUserID else { return }
        let lastOpening = todaysQuestionOpenings.lastOpening(userID: userID)
        switch todaysQuestionCheck.action(lastOpening: lastOpening, now: .now) {
        case .none:
            return
        case .startWindow:
            todaysQuestionVisit = .ready(since: .now)
        case .decide:
            todaysQuestionVisit = .decided
        case let .wait(deadline):
            try? await Task.sleep(until: deadline)
            if !Task.isCancelled { todaysQuestionVisit = .decided }
        case .openInPlace:
            // On a cold launch the launch screen fades straight into the question.
            openTodaysQuestionInPlace(curtain: launchOverlayShowing ? .launchScreen : nil)
            todaysQuestionVisit = .opened
        case .openWithZoom:
            openAnswerFlow(source: .us)
            todaysQuestionVisit = .opened
        }
    }
}

private extension PaeoniaDeepLink {
    var opensTodaysQuestion: Bool {
        switch self {
        case .dailyToday, .firstDayAnswer: true
        default: false
        }
    }
}
