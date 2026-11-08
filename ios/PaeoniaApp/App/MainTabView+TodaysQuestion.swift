import SwiftUI

/// One visit to the app, from a cold launch or a return from the background, as far as
/// opening today's question by itself goes.
enum TodaysQuestionVisit: Equatable {
    /// Waiting for the app to be in front, past the launch intro and unlocked.
    case starting
    /// In front, past the intro and unlocked since `since`.
    case ready(since: ContinuousClock.Instant)
    /// Nothing more happens until the next visit. The question opened, the visit came
    /// with a destination, the person was elsewhere, or the time to decide ran out.
    case decided
}

/// What decides whether today's question opens by itself right now.
struct TodaysQuestionCheck: Equatable {
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
        /// Open once Home's envelope has settled, if that is still before `deadline`.
        case open(by: ContinuousClock.Instant)
    }

    /// The question opens within this time of the app being ready, or not at all, so a
    /// slow load never interrupts someone already using the app.
    static let window: Duration = .seconds(4)

    let visit: TodaysQuestionVisit
    let isAppReady: Bool
    /// Home is in front, with nothing presented over it.
    let isHomeInFront: Bool
    /// Nil while the card loads, after the user answered, or while it still shows a day
    /// that has ended.
    let openable: Openable?

    func action(lastOpening: TodaysQuestionOpening?) -> Action {
        switch visit {
        case .decided:
            return .none
        case .starting:
            return isAppReady ? .startWindow : .none
        case let .ready(since):
            guard isAppReady else { return .none }
            guard isHomeInFront else { return .decide }
            let deadline = since + Self.window
            guard let openable, TodaysQuestionOpening.mayOpen(
                on: openable.day, partnerHasAnswered: openable.partnerHasAnswered, after: lastOpening
            ) else { return .wait(until: deadline) }
            return .open(by: deadline)
        }
    }
}

/// Opens today's question by itself on a plain open of the app, at most once a couple
/// day, and once more when the partner has answered since. Only `RootView` gives
/// `MainTabView` a store, so developer flows and UI tests never see it.
extension MainTabView {
    /// Long enough for Home's envelope to finish its 0.7 s fade-in
    /// (`PaeoniaMotion.loadingReveal`) before the cover zooms out of it.
    private static let todaysQuestionSettleDelay: Duration = .milliseconds(800)

    func openingTodaysQuestion(on content: some View) -> some View {
        content
            // A visit starts on leaving, because a notification tap can arrive just
            // before or just after the app becomes active.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { todaysQuestionVisit = .starting }
            }
            // A push, widget, link, Siri or Spotlight brought the person somewhere.
            .onChange(of: deepLink.wrappedValue != nil, initial: true) { _, hasLink in
                if hasLink { todaysQuestionVisit = .decided }
            }
            .onChange(of: widgetDrawingPresented.wrappedValue, initial: true) { _, isPresented in
                if isPresented { todaysQuestionVisit = .decided }
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

    private var todaysQuestionCheck: TodaysQuestionCheck {
        TodaysQuestionCheck(
            visit: todaysQuestionVisit,
            isAppReady: scenePhase == .active && launchIntroComplete && !AppLockModel.shared.isCovering,
            isHomeInFront: selection.wrappedValue == .us
                && !isAnswerFlowPresented
                && partnerAnswerQuestion == nil
                && !showStreakRestore
                && !showStreakDetail
                && streakMilestone == nil
                && !isSearchPresented
                && !widgetDrawingPresented.wrappedValue
                && dailyChatQuestion == nil
                && gameChatSheet == nil
                && !isLookBackDrawingHistoryPresented,
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
        switch todaysQuestionCheck.action(lastOpening: todaysQuestionOpenings.lastOpening(userID: userID)) {
        case .none:
            return
        case .startWindow:
            todaysQuestionVisit = .ready(since: .now)
        case .decide:
            todaysQuestionVisit = .decided
        case let .wait(deadline):
            try? await Task.sleep(until: deadline)
            if !Task.isCancelled { todaysQuestionVisit = .decided }
        case let .open(deadline):
            await openTodaysQuestionOnceSettled(by: deadline)
        }
    }

    private func openTodaysQuestionOnceSettled(by deadline: ContinuousClock.Instant) async {
        let settled = ContinuousClock.now + Self.todaysQuestionSettleDelay
        guard await startTodayIfNeeded() else {
            todaysQuestionVisit = .decided
            return
        }
        try? await Task.sleep(until: settled)
        guard !Task.isCancelled else { return }
        openTodaysQuestion(by: deadline)
    }

    /// The server makes the day's question when someone first opens it. Making it before
    /// the cover opens means a phone that is offline, or a server that refuses, never opens
    /// a cover that only says it went wrong. The envelope stays for a tap instead.
    private func startTodayIfNeeded() async -> Bool {
        let model = dailyChallengeViewModel
        guard model.homeCardState.kind == .noChallenge else { return true }
        await model.startToday()
        guard !Task.isCancelled else { return false }
        if case .active = model.homeCardState.kind { return true }
        if case .startFailed = model.notice { model.dismissNotice() }
        return false
    }

    private func openTodaysQuestion(by deadline: ContinuousClock.Instant) {
        guard ContinuousClock.now <= deadline else {
            todaysQuestionVisit = .decided
            return
        }
        openAnswerFlow(source: .us)
    }
}
