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
            // The Home card waits for the flow to close before its seal breaks.
            .environment(\.dailyFlowIsPresented, isAnswerFlowPresented)
            .fullScreenCover(isPresented: $isAnswerFlowPresented, onDismiss: offerNotificationsIfAnswered) {
                DailyChallengeAnswerFlow(
                    viewModel: dailyChallengeViewModel,
                    onClose: closeAnswerFlow,
                    makeStreakRestoreViewModel: makeStreakRestoreViewModel,
                    onOpenPartnerQuestions: openQuestionsTabFromAnswerFlow,
                    claimStreakMilestone: claimStreakMilestone,
                    onOpenQuestionChat: openQuestionChatFromAnswerFlow
                )
                .analyticsScreen("daily_answer")
                .zoomTransition(dailyFlowSource.zoomSourceID, in: zoomNamespace, enabled: !reduceMotion)
                .environment(bannerCenter)
                .paeoniaTopBanner(bannerCenter)
            }
            // The single-question partner-answer flow zooms out of the tapped card.
            .fullScreenCover(
                item: $partnerAnswerQuestion,
                onDismiss: offerNotificationsIfAnswered,
                content: partnerAnswerFlow
            )
            // The streak badge opens the restore offer (broken) from outside the answer flow.
            .sheet(isPresented: $showStreakRestore) {
                StreakRestoreView(
                    viewModel: makeStreakRestoreViewModel(),
                    onClose: { showStreakRestore = false }
                )
                .analyticsScreen("streak_restore")
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
                .analyticsScreen("streak_detail")
                .presentationDetents([.large])
                .presentationBackground(.paeoniaSurfacePrimary)
            }
    }

    /// Runs once the cover is gone, so the notification ask can show. It waits for the
    /// Home card's seal moment to finish first.
    private func offerNotificationsIfAnswered() {
        guard dailyChallengeViewModel.hasSentAnswer else { return }
        let share = PartnerShare.answer(awaitsPartner: dailyChallengeViewModel.takeAnswerAwaitingPartner())
        Task {
            try? await Task.sleep(for: DailyPromptCard.momentLength)
            actions.sentSomethingToPartner(share)
        }
    }

    /// Answering a question the partner already answered. Sending it turns the
    /// cover into the question's chat.
    private func partnerAnswerFlow(for question: DailyChallengeQuestion) -> some View {
        Group {
            if question.isTopicQuestion {
                topicAnswerSession(for: question)
            } else {
                DailyPartnerAnswerFlow(
                    question: question,
                    viewModel: dailyChallengeViewModel,
                    privacySafetyService: dependencies.settingsPrivacyService,
                    privacyOperationProvider: dependencies.settingsPrivacyOperationProvider,
                    onReportedAndLeft: actions.leftRelationship,
                    onClose: closePartnerAnswerFlow
                )
            }
        }
        .zoomTransition(partnerAnswerZoomSourceID(for: question), in: zoomNamespace, enabled: !reduceMotion)
        .environment(bannerCenter)
        .paeoniaTopBanner(bannerCenter)
    }

    /// The row the partner-answer flow zooms out of: the locked row on the Home card
    /// when it opened from there, otherwise the question's row in the Questions tab.
    private func partnerAnswerZoomSourceID(for question: DailyChallengeQuestion) -> AnyHashable {
        partnerAnswerOpenedFromHome
            ? AnyHashable(DailyFlowZoom.homePartnerQuestion(question.id))
            : AnyHashable(question.id)
    }

    /// The milestone moment sheet, and the check that opens it.
    private func presentingStreakMilestones(on content: some View) -> some View {
        content
            .sheet(item: $streakMilestone) { moment in
                StreakMilestoneView(days: moment.days, onClose: { streakMilestone = nil })
                    .analyticsScreen("streak_milestone")
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
            openPartnerQuestionsInQuestionsTab()
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
        openPartnerQuestionsInQuestionsTab()
        isAnswerFlowPresented = false
    }

    /// Lands on the Questions tab with the partner's waiting questions outlined, so
    /// the user can see which rows the button meant.
    private func openPartnerQuestionsInQuestionsTab() {
        selection.wrappedValue = .questions
        focusedDailyQuestionIDs = dailyChallengeViewModel.snapshot.answerablePartnerQuestions.map(\.id)
    }

    /// The note about an earlier answer: closes the flow and opens the question's chat,
    /// scrolled to the day the user just answered, with the earlier days above it.
    private func openQuestionChatFromAnswerFlow(_ question: DailyChallengeQuestion) {
        isAnswerFlowPresented = false
        startOpeningDailyChat(instanceID: question.id)
    }

    private func closeAnswerFlow() {
        if returnsToQuestionsOnClose {
            selection.wrappedValue = .questions
        }
        isAnswerFlowPresented = false
    }

    func openPartnerAnswerFlow(_ question: DailyChallengeQuestion) {
        partnerAnswerOpenedFromHome = false
        withAnimation(zoomPresentationAnimation) {
            partnerAnswerQuestion = question
        }
    }

    /// A locked row on the Home card opens the same single-question flow.
    func openPartnerQuestionFromHome(_ id: UUID) {
        guard let question = dailyChallengeViewModel.snapshot.questions.first(where: { $0.id == id }) else { return }
        partnerAnswerOpenedFromHome = true
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
        case .subscription, .dataExport:
            // RootView owns these: it opens App Store subscription management or the
            // data download screen, then consumes the link. Acting here as well would
            // race the root task.
            break
        case .dailyReveal, .dailyChat, .dailyToday, .topics:
            await handleQuestionsDeepLink(deepLink)
        case .memories, .memory:
            await openMemories(for: deepLink)
        case let .game(kind):
            await openGame(kind, for: deepLink)
        case .streak:
            await openStreak(for: deepLink)
        case .stories, .home, .dates, .story:
            await openHome(for: deepLink)
        }
    }

    /// Opens Home. A link to one story also opens it in the viewer, once the stories are read.
    /// The dates timeline opens on top for a date reminder.
    private func openHome(for deepLink: PaeoniaDeepLink) async {
        selection.wrappedValue = .home
        if deepLink == .dates {
            coupleDatesViewModel.requestTimeline()
        }
        if case let .story(storyID, showsReplies) = deepLink {
            await storiesViewModel.reload()
            guard isCurrent(deepLink) else { return }
            storiesViewModel.requestOpen(storyID: storyID, showsReplies: showsReplies)
        }
        self.deepLink.wrappedValue = nil
    }

    /// Opens the Memories tab. A link to one memory also opens it, after reading the memories
    /// when it is not on this phone yet. A memory that is gone leaves the person on the timeline.
    private func openMemories(for deepLink: PaeoniaDeepLink) async {
        selection.wrappedValue = .memories
        if case let .memory(memoryID, showsComments) = deepLink {
            if memoriesViewModel.record(for: memoryID) == nil {
                await memoriesViewModel.refresh()
                guard isCurrent(deepLink) else { return }
            }
            if memoriesViewModel.record(for: memoryID) != nil {
                memoriesPath = [memoryID]
                if showsComments { memoriesViewModel.commentsRequestedMemoryID = memoryID }
            }
        } else {
            await memoriesViewModel.refresh()
            guard isCurrent(deepLink) else { return }
        }
        self.deepLink.wrappedValue = nil
    }

    private func openStreak(for deepLink: PaeoniaDeepLink) async {
        selection.wrappedValue = .home
        // The streak may have advanced, broken, or passed its restore deadline
        // since the notification was queued. Refresh before choosing the one
        // destination so a broken streak opens the purchase offer directly.
        guard await refreshStillCurrent(for: deepLink) else { return }
        openStreakDetails()
        self.deepLink.wrappedValue = nil
    }

    /// Opens a game from a notification or an invite. Someone who has not been
    /// through the first-time steps sees them before the game. A game this build
    /// does not have opens the hub.
    private func openGame(_ kind: GameKind, for deepLink: PaeoniaDeepLink) async {
        selection.wrappedValue = .games
        gamesViewModel.configure(participants: gamesParticipants)
        await gamesViewModel.load()
        guard isCurrent(deepLink) else { return }
        if gamesViewModel.game(kind) != nil {
            gamesViewModel.open(.game(kind))
        }
        self.deepLink.wrappedValue = nil
    }

    /// A game card on Home, shown while the partner is in the game, or the banner
    /// other tabs show when the partner opens one. Someone who has not been through
    /// the first-time steps sees them before the game.
    func openGameFromHome(_ destination: GamesDestination) {
        selection.wrappedValue = .games
        gamesViewModel.open(destination)
    }

    /// The partner just opened `kind`. Home already shows the game's card, and a
    /// person already in that game, or in the middle of answering, gets no banner.
    func announcePartnerGame(_ kind: GameKind?) {
        guard let kind, selection.wrappedValue != .home,
              !(selection.wrappedValue == .games && gamesPath.contains(.game(kind))),
              !isAnswerFlowPresented, partnerAnswerQuestion == nil
        else { return }

        let gameName = String(localized: kind.name)
        bannerCenter.show(
            .info(
                title: String(localized: .gamesPartnerOpenedTitle(gamesViewModel.partnerName, gameName)),
                message: String(localized: .gamesPartnerOpenedMessage),
                imageData: PaeoniaAppGroup.partnerAvatarData(),
                systemImage: "gamecontroller.fill",
                action: { openGameFromHome(.game(kind)) },
                // Longer than other notices: the invite only helps while the partner is still in the game.
                timing: .fixed(.seconds(7))
            )
        )
    }

    /// Links into the Questions tab refresh first, so a partner's answer or a
    /// new day is on screen before the question is focused or opened.
    private func handleQuestionsDeepLink(_ deepLink: PaeoniaDeepLink) async {
        selection.wrappedValue = .questions
        guard await refreshStillCurrent(for: deepLink) else { return }

        switch deepLink {
        case .dailyReveal(let instanceID, _):
            focusedDailyQuestionIDs = [instanceID]
        case .dailyChat(let questionID):
            await openDailyChat(questionID: questionID)
            guard isCurrent(deepLink) else { return }
        case .dailyToday:
            if dailyChallengeViewModel.homeCardState.kind != .complete {
                openAnswerFlow(source: .questions)
            }
        case .topics:
            openTopics()
        default:
            return
        }
        self.deepLink.wrappedValue = nil
    }

    /// Opens a question's chat on the Questions tab at its newest day, from a
    /// notification or the Home unread chats card. A couple has one chat per question.
    func openDailyChat(questionID: UUID) async {
        var question = await dailyChallengeViewModel.questionForChat(questionID: questionID)
        if question == nil {
            question = await topicChatQuestion(questionID: questionID)
        }
        await presentDailyChat(question, focusesNewest: true)
    }

    /// Opens the chat of the question that one day belongs to, scrolled to that day.
    func openDailyChat(instanceID: UUID) async {
        await presentDailyChat(
            await dailyChallengeViewModel.questionForChat(instanceID: instanceID),
            focusesNewest: false
        )
    }

    private func presentDailyChat(_ question: DailyChallengeQuestion?, focusesNewest: Bool) async {
        selection.wrappedValue = .questions
        if let question {
            await dailyChallengeViewModel.prepareChat(for: question, focusesNewest: focusesNewest)
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

    func startOpeningDailyChat(questionID: UUID) {
        Task { await openDailyChat(questionID: questionID) }
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
