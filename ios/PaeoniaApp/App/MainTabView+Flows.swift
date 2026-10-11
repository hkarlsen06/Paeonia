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
        content
            .fullScreenCover(isPresented: $isAnswerFlowPresented) {
                DailyChallengeAnswerFlow(
                    viewModel: dailyChallengeViewModel,
                    onClose: closeAnswerFlow,
                    makeStreakRestoreViewModel: makeStreakRestoreViewModel,
                    onOpenPartnerQuestions: openQuestionsTabFromAnswerFlow
                )
                .zoomTransition(dailyFlowSource.zoomSourceID, in: zoomNamespace, enabled: !reduceMotion)
                .environment(bannerCenter)
                .paeoniaTopBanner(bannerCenter)
            }
            // The single-question partner-answer flow zooms out of the tapped card.
            .fullScreenCover(item: $partnerAnswerQuestion) { question in
                DailyPartnerAnswerFlow(
                    question: question,
                    viewModel: dailyChallengeViewModel,
                    onClose: closePartnerAnswerFlow
                )
                .zoomTransition(question.id, in: zoomNamespace, enabled: !reduceMotion)
                .environment(bannerCenter)
                .paeoniaTopBanner(bannerCenter)
            }
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
            onRestored: { count in
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

    func openDailyChallengeFromHome() {
        let state = dailyChallengeViewModel.homeCardState
        if state.kind == .complete, state.hasPartnerAnswersForToday {
            selection.wrappedValue = .questions
            return
        }

        openAnswerFlow(source: .home)
    }

    /// Today's questions are created lazily, so opening the flow before the couple
    /// has started kicks off that one-time setup; the flow shows a brief loading
    /// state until the questions arrive.
    func openAnswerFlow(source: DailyFlowSource) {
        if dailyChallengeViewModel.homeCardState.kind == .noChallenge {
            Task { await dailyChallengeViewModel.startToday() }
        }
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

    private func refreshStillCurrent(for deepLink: PaeoniaDeepLink) async -> Bool {
        await refreshDailyChallenge()
        return isCurrent(deepLink)
    }

    private func isCurrent(_ deepLink: PaeoniaDeepLink) -> Bool {
        !Task.isCancelled && self.deepLink.wrappedValue == deepLink
    }
}
