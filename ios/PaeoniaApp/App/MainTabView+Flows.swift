import SwiftUI

/// Which entry card the daily answer flow zooms out of.
enum DailyFlowSource {
    case home
    case questions

    var zoomSourceID: String {
        switch self {
        case .home: DailyFlowZoom.home
        case .questions: DailyFlowZoom.questions
        }
    }
}

/// The daily answer flows, the streak sheets, and notification deep links.
extension MainTabView {
    /// The answer flow is a full-screen cover that zooms out of the card that opened
    /// it (covering the floating tab bar). Reduce Motion drops the zoom for the
    /// cover's plain cross-fade. A slipped streak's completion screen buys the
    /// streak back in place (see `makeStreakRestoreViewModel`), rather than opening a
    /// second, near-identical restore screen over the cover. Each cover mounts the
    /// shared top banner, because the root's banner would sit behind it.
    func presentingDailyFlows(on content: some View) -> some View {
        presentingStreakMilestones(on: content)
            .fullScreenCover(isPresented: $isAnswerFlowPresented) {
                DailyChallengeAnswerFlow(
                    viewModel: dailyChallengeViewModel,
                    onClose: closeAnswerFlow,
                    makeStreakRestoreViewModel: makeStreakRestoreViewModel,
                    onOpenPartnerQuestions: openQuestionsTabFromAnswerFlow,
                    claimStreakMilestone: claimStreakMilestone
                )
                .zoomTransition(dailyFlowSource.zoomSourceID, in: zoomNamespace, enabled: !reduceMotion)
                .environment(bannerCenter)
                .paeoniaTopBanner(bannerCenter)
            }
            // The single-question partner-answer flow zooms out of the tapped card.
            .fullScreenCover(item: $partnerAnswerQuestion, content: partnerAnswerFlow)
            // The streak badge opens the restore offer (broken) from outside the answer flow.
            .sheet(isPresented: $showStreakRestore) {
                StreakRestoreView(
                    viewModel: makeStreakRestoreViewModel(),
                    onClose: { showStreakRestore = false }
                )
                .presentationDetents([.large])
                .presentationBackground(.paeoniaSurfacePrimary)
                .paeoniaTopBanner(bannerCenter)
            }
            // …or the read-only detail sheet when the streak is healthy.
            .sheet(isPresented: $showStreakDetail) {
                StreakDetailView(
                    streak: dailyChallengeViewModel.streak,
                    onClose: { showStreakDetail = false }
                )
                .presentationDetents([.large])
                .presentationBackground(.paeoniaSurfacePrimary)
            }
    }

    /// Answering a question the partner already answered. Sending it turns the
    /// cover into the question's chat.
    private func partnerAnswerFlow(for question: DailyChallengeQuestion) -> some View {
        DailyPartnerAnswerFlow(
            question: question,
            viewModel: dailyChallengeViewModel,
            privacySafetyService: dependencies.settingsPrivacyService,
            privacyOperationProvider: dependencies.settingsPrivacyOperationProvider,
            onReportedAndLeft: actions.leftRelationship,
            onClose: closePartnerAnswerFlow
        )
        .zoomTransition(question.id, in: zoomNamespace, enabled: !reduceMotion)
        .environment(bannerCenter)
        .paeoniaTopBanner(bannerCenter)
    }

    /// The milestone moment sheet, and the check that opens it.
    private func presentingStreakMilestones(on content: some View) -> some View {
        content
            .sheet(item: $streakMilestone) { moment in
                StreakMilestoneView(days: moment.days, onClose: { streakMilestone = nil })
                    .presentationDetents([.large])
                    .presentationBackground(.paeoniaSurfacePrimary)
            }
            // Checks again whenever the count changes and whenever the screen is free,
            // so a milestone reached while another sheet was open still shows after it.
            .onChange(of: streakMilestoneCheck, initial: true) {
                celebrateStreakMilestoneIfDue()
            }
    }

    private var streakMilestoneStore: StreakMilestoneStore { StreakMilestoneStore() }

    private var streakMilestoneCheck: StreakMilestoneCheck {
        StreakMilestoneCheck(
            count: dailyChallengeViewModel.streak.currentCount,
            userID: identity.currentUserID,
            isScreenBusy: scenePhase != .active
                || !launchIntroComplete
                || isAnswerFlowPresented
                || partnerAnswerQuestion != nil
                || showStreakRestore
                || showStreakDetail
                || streakMilestone != nil
        )
    }

    /// Shows the milestone moment when the streak reaches a milestone this phone has
    /// not celebrated. Waits while the app is in the background, the launch intro is
    /// playing, or another flow or sheet is open. The answer flow claims the milestone
    /// itself on its completion screen.
    private func celebrateStreakMilestoneIfDue() {
        let check = streakMilestoneCheck
        guard !check.isScreenBusy, !dailyChallengeViewModel.streak.isRestorable,
              let days = claimStreakMilestone(check.count)
        else { return }
        streakMilestone = StreakMilestoneMoment(days: days)
    }

    private func claimStreakMilestone(_ count: Int) -> Int? {
        guard let userID = identity.currentUserID else { return nil }
        return streakMilestoneStore.claim(count: count, userID: userID)
    }

    /// Keep full-screen cover insertion in the same transaction as the native zoom.
    /// Without an explicit transaction, SwiftUI can briefly draw the destination at its
    /// final full-screen size before the zoom animator takes over.
    private var zoomPresentationAnimation: Animation? {
        reduceMotion ? nil : PaeoniaMotion.heroMorph
    }

    /// Tapping the streak badge. A broken streak that can still be bought back opens
    /// the restore offer; an intact streak opens the read-only detail sheet.
    func openStreakDetails() {
        switch dailyChallengeViewModel.streak.entryDestination {
        case .restore:
            showStreakRestore = true
        case .detail:
            showStreakDetail = true
        case .milestone(let days):
            streakMilestone = StreakMilestoneMoment(days: days)
        }
    }

    /// Builds a streak-restore purchase view model bound to the current streak and
    /// signed-in user. Shared by the badge-opened restore sheet and the answer flow's
    /// completion screen, so a restore refreshes the streak whichever path bought it.
    private func makeStreakRestoreViewModel() -> StreakRestoreViewModel {
        let dailyChallengeViewModel = dailyChallengeViewModel
        return StreakRestoreViewModel(
            streak: dailyChallengeViewModel.streak,
            userID: identity.currentUserID?.uuidString,
            onRestored: { [identity] count in
                // A streak bought back has its own celebration, so skip the milestones it passes.
                if let userID = identity.currentUserID {
                    StreakMilestoneStore().markRestored(upTo: count, userID: userID)
                }
                dailyChallengeViewModel.applyRestoredStreak(count)
                await dailyChallengeViewModel.refreshStreak()
            },
            // Re-read before buying, so a streak the partner already brought back
            // (or whose time ran out) is never paid for again.
            latestStreak: {
                await dailyChallengeViewModel.refreshStreak()
                return dailyChallengeViewModel.streak
            }
        )
    }

    /// Keep the daily challenge refresh visually responsive. Read the challenge first
    /// so partner answers and day rollover appear without waiting for broader app sync,
    /// then sync and read once more in case that sync flushed a queued local answer.
    func refreshDailyChallenge() async {
        await dailyChallengeViewModel.reload()
        await actions.refreshDailyChallenge()
        await dailyChallengeViewModel.reload()
    }

    /// Matches the Home card's label. "See partner's answers" goes straight to the
    /// Questions tab. "See your answers" opens the user's answers first, then lands
    /// on the Questions tab when the partner has answers to read there.
    func openDailyChallengeFromHome() {
        let state = dailyChallengeViewModel.homeCardState
        if state.kind == .complete, state.hasAnswerablePartnerQuestions {
            selection.wrappedValue = .questions
            return
        }

        openAnswerFlow(
            source: .home,
            returnsToQuestions: state.kind == .complete && state.hasPartnerAnswersForToday
        )
    }

    /// Today's questions are created lazily, so opening the flow before the couple
    /// has started kicks off that one-time setup; the flow shows a brief loading
    /// state until the questions arrive.
    func openAnswerFlow(source: DailyFlowSource, returnsToQuestions: Bool = false) {
        if dailyChallengeViewModel.homeCardState.kind == .noChallenge {
            Task { await dailyChallengeViewModel.startToday() }
        }
        returnsToQuestionsOnClose = returnsToQuestions
        withAnimation(zoomPresentationAnimation) {
            dailyFlowSource = source
            isAnswerFlowPresented = true
        }
    }

    private func openQuestionsTabFromAnswerFlow() {
        selection.wrappedValue = .questions
        isAnswerFlowPresented = false
    }

    private func closeAnswerFlow() {
        if returnsToQuestionsOnClose {
            selection.wrappedValue = .questions
        }
        isAnswerFlowPresented = false
    }

    func openPartnerAnswerFlow(_ question: DailyChallengeQuestion) {
        withAnimation(zoomPresentationAnimation) {
            partnerAnswerQuestion = question
        }
    }

    private func closePartnerAnswerFlow() {
        partnerAnswerQuestion = nil
    }

    /// Opens a notification's destination. Every case that waits for a refresh
    /// checks afterwards that it is still the current link: `.task(id:)` cancels
    /// this handler when a newer link arrives, and the older one must neither
    /// act on stale state nor clear the newer link.
    @MainActor
    func handleDeepLink(_ deepLink: PaeoniaDeepLink?) async {
        guard let deepLink else {
            return
        }

        switch deepLink {
        case .widgetDrawing:
            actions.openWidgetDrawing()
            self.deepLink.wrappedValue = nil
        case .subscription:
            // RootView owns this: it opens App Store subscription management and
            // then consumes the link. Acting here as well would race the root task.
            break
        case .dailyReveal, .dailyChat, .dailyToday:
            await handleQuestionsDeepLink(deepLink)
        case .memories:
            selection.wrappedValue = .memories
            await memoriesViewModel.refresh()
            guard isCurrent(deepLink) else { return }
            self.deepLink.wrappedValue = nil
        case .streak:
            selection.wrappedValue = .home
            // The streak may have advanced, broken, or passed its restore deadline
            // since the notification was queued. Refresh before choosing the one
            // destination so a broken streak opens the purchase offer directly.
            guard await refreshStillCurrent(for: deepLink) else { return }
            openStreakDetails()
            self.deepLink.wrappedValue = nil
        }
    }

    /// Links into the Questions tab refresh first, so a partner's answer or a
    /// new day is on screen before the question is focused or opened.
    private func handleQuestionsDeepLink(_ deepLink: PaeoniaDeepLink) async {
        selection.wrappedValue = .questions
        guard await refreshStillCurrent(for: deepLink) else { return }

        switch deepLink {
        case .dailyReveal(let instanceID, _):
            focusedDailyQuestionID = instanceID
        case .dailyChat(let instanceID):
            await openDailyChat(instanceID: instanceID)
            guard isCurrent(deepLink) else { return }
        case .dailyToday:
            if dailyChallengeViewModel.homeCardState.kind != .complete {
                openAnswerFlow(source: .questions)
            }
        default:
            return
        }
        self.deepLink.wrappedValue = nil
    }

    /// Opens a question's chat on the Questions tab, from a notification or the
    /// Home unread chats card.
    func openDailyChat(instanceID: UUID) async {
        selection.wrappedValue = .questions
        let question = await dailyChallengeViewModel.questionForChat(instanceID: instanceID)
        if let question {
            await dailyChallengeViewModel.prepareChat(for: question)
        }
        guard !Task.isCancelled else { return }

        dailyChatQuestion = question
        if question == nil {
            bannerCenter.show(
                .error(
                    title: String(localized: .dailyChatErrorUnavailableTitle),
                    message: String(localized: .dailyChatErrorUnavailableMessage)
                )
            )
        }
    }

    func startOpeningDailyChat(instanceID: UUID) {
        Task { await openDailyChat(instanceID: instanceID) }
    }

    private func refreshStillCurrent(for deepLink: PaeoniaDeepLink) async -> Bool {
        await refreshDailyChallenge()
        return isCurrent(deepLink)
    }

    private func isCurrent(_ deepLink: PaeoniaDeepLink) -> Bool {
        !Task.isCancelled && self.deepLink.wrappedValue == deepLink
    }
}
