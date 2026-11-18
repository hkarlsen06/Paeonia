import Foundation
import SwiftUI
import UIKit

/// The five tabs and the views they show.
extension MainTabView {
    var tabNavigation: some View {
        TabView(selection: tabViewSelection) {
            ForEach(tabs) { tab in
                Tab(value: tab) {
                    tabRoot(for: tab)
                        .paeoniaBannerBottomEdge(at: .bottom, isActive: tab == selection.wrappedValue)
                        .toolbarVisibility(gameTabBarVisibility, for: .tabBar)
                        .modifier(TabBarPlacementReporter { tabBarPlacement = $0 })
                        .onGeometryChange(for: CGFloat.self) {
                            $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom
                        } action: { bottom in
                            guard tab == .questions else { return }
                            gameChatReturn.layout.chatBottom = bottom
                        }
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .badge(badgeCount(for: tab))
                .accessibilityIdentifier("mainTab.\(tab.rawValue)")
            }
        }
        .revealedAfterPassThrough(self)
        .paeoniaBanner(
            bannerCenter,
            onTap: actions.openWidgetDrawing
        )
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom
        } action: { bottom in
            gameChatReturn.layout.containerBottom = bottom
        }
        .onDockedKeyboardChange { gameChatReturn.layout.isKeyboardDocked = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            gameChatReturn.layout.waitsForKeyboard = false
        }
        .onChange(of: selection.wrappedValue) { _, tab in
            gameChatTabChanged(to: tab)
            gameChatReturn.isPending = false
            gameChatReturn.layout.waitsForKeyboard = false
            gameChatReturn.layout.layoutReadyFrame = nil
        }
        .onChange(of: gamesPath) { _, path in gamesPathChanged(to: path) }
        .onChange(of: gameChatDestination?.id) { _, _ in
            gameChatReturn.isPending = false
            gameChatReturn.layout.waitsForKeyboard = false
            gameChatReturn.layout.layoutReadyFrame = nil
        }
        .overlay {
            if gameChatReturn.isPending {
                TimelineView(.animation) { context in
                    Color.clear.onChange(of: context.date, initial: true) { _, frame in
                        finishGameChatReturn(after: frame)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// Declare visibility above the tab stacks, before the selected stack appears.
    private var gameTabBarVisibility: Visibility {
        (gameChatReturn.isPending || selection.wrappedValue == .games && !gamesPath.isEmpty)
            && hidesTabBarInGames
            ? .hidden : .automatic
    }

    /// A bar along the top leaves a game its space. A bottom or side bar takes it.
    private var hidesTabBarInGames: Bool {
        tabBarPlacement != .topBar
    }

    func selectTab(_ tab: MainTab) {
        if tab == .games, selection.wrappedValue == .questions, !gamesPath.isEmpty, hidesTabBarInGames {
            guard !gameChatReturn.isPending else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                gameChatReturn.isPending = true
                gameChatReturn.layout.waitsForKeyboard = gameChatReturn.layout.isKeyboardDocked
                gameChatReturn.layout.layoutReadyFrame = nil
            }
            PaeoniaKeyboard.dismiss()
            return
        }
        gameChatReturn.isPending = false
        gameChatReturn.layout.layoutReadyFrame = nil
        // A chat waiting for Games to show its game no longer opens.
        if tab != .games { pendingGameChatSheet = nil }
        PaeoniaKeyboard.dismiss()
        guard !gamesPath.isEmpty, selection.wrappedValue == .games || tab == .games else {
            selection.wrappedValue = tab
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { selection.wrappedValue = tab }
    }

    private func finishGameChatReturn(after frame: Date) {
        guard gameChatReturn.isReady else {
            gameChatReturn.layout.layoutReadyFrame = nil
            return
        }
        guard let readyFrame = gameChatReturn.layout.layoutReadyFrame else {
            gameChatReturn.layout.layoutReadyFrame = frame
            return
        }
        guard frame != readyFrame else { return }
        gameChatReturn.isPending = false
        gameChatReturn.layout.layoutReadyFrame = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { selection.wrappedValue = .games }
    }

    @ViewBuilder
    func content(for tab: MainTab) -> some View {
        switch tab {
        case .us:
            usTab
        case .questions:
            questionsTab
        case .games:
            gamesTab
        case .settings:
            settingsTab
        case .memories:
            memoriesTab
        }
    }

    var mailViewModel: MailViewModel { models.mail }

    func badgeCount(for tab: MainTab) -> Int {
        switch tab {
        // The server's counts, the same ones the app icon adds up. Questions includes
        // the unread memory and story chats, since its list shows them. Home counts
        // the stories and letters from this phone's own lists, so opening one clears it at once.
        case .questions: AppBadges.shared.counts.questions
        case .games: AppBadges.shared.counts.games
        case .us:
            StoryTimeline.unseenCount(storiesViewModel.stories, partner: identity.partnerUserID, at: storyBadgeDate)
                + mailViewModel.waiting.count
        case .memories, .settings: 0
        }
    }

    private var gamesTab: some View {
        clearingGamesBadge(
            on: GamesRootView(viewModel: gamesViewModel, path: $gamesPath, tabBarVisibility: gameTabBarVisibility)
                .gameChatPanel($gameChatSheet, onClosed: gameChatClosed)
                .environment(\.gameChatIsOpen, gameChatIsOpen)
        )
    }

    var gamesParticipants: GameParticipants {
        GameParticipants(
            currentUserID: identity.currentUserID,
            coupleID: identity.coupleID,
            partnerName: dailyChallengeParticipants.partnerName,
            currentName: identity.currentDisplayName ?? String(localized: .dailyChallengeChoiceYou),
            currentPhotoAssetID: identity.currentProfilePhotoAssetID,
            partnerPhotoAssetID: identity.partnerProfilePhotoAssetID,
            currentSharedName: identity.currentDisplayName,
            partnerSharedName: identity.partnerName?.sharedName
        )
    }

    var storyPeople: StoryPeople {
        StoryPeople(
            currentUserID: identity.currentUserID,
            currentName: identity.currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName),
            currentPhotoAssetID: identity.currentProfilePhotoAssetID,
            partnerUserID: identity.partnerUserID,
            partnerName: dailyChallengeParticipants.partnerName,
            partnerPhotoAssetID: identity.partnerProfilePhotoAssetID
        )
    }

    /// Counts the Us tab badge again now, then again each time an unseen story
    /// leaves Home, until the stories or the partner change and the task restarts.
    func refreshStoryBadge() async {
        while !Task.isCancelled {
            let now = Date()
            storyBadgeDate = now
            guard let expiry = StoryTimeline.nextUnseenExpiry(
                storiesViewModel.stories,
                partner: identity.partnerUserID,
                at: now
            ) else { return }
            do {
                try await Task.sleep(for: .seconds(expiry.timeIntervalSince(now)))
            } catch {
                return
            }
        }
    }

    private var memoriesTab: some View {
        NavigationStack(path: $memoriesPath) {
            MemoriesScreen(
                currentUserID: identity.currentUserID,
                viewModel: memoriesViewModel,
                stories: storiesViewModel,
                storyPeople: storyPeople,
                gameRounds: gamesViewModel.guessMySpot.history
            )
            .searchToolbarButton(action: openSearch)
            .analyticsScreen("memories")
        }
    }

    private var usTab: some View {
        NavigationStack {
            // Home hides its navigation bar and draws the brand mark and streak in its
            // own header. Screens pushed from it keep their bar.
            withRecap(pairedHome)
                // Shows only where Home has a navigation bar, on a wide iPad.
                .searchToolbarButton(placement: .topBarTrailing, action: openSearch)
                .analyticsScreen("us")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: widgetDrawingPresented) {
                    WidgetDrawingView(
                        ownerUserID: identity.currentUserID,
                        coupleID: identity.coupleID,
                        authorName: identity.currentDisplayName,
                        viewModel: dependencies.widgetDrawingViewModel,
                        historyViewModel: dependencies.widgetHistoryViewModel,
                        historyThumbnailLoader: dependencies.widgetHistoryThumbnailLoader
                    )
                    .analyticsScreen("widget_drawing")
                }
                .lookBackDrawingHistory(
                    isPresented: $isLookBackDrawingHistoryPresented,
                    revisionID: lookBackDrawingRevisionID, dependencies: dependencies
                )
                .mailSheet(mailViewModel, people: MailPeople(
                    currentUserID: identity.currentUserID,
                    partnerUserID: identity.partnerUserID,
                    partnerName: dailyChallengeParticipants.partnerName,
                    onReportedAndLeft: actions.leftRelationship
                ))
                .onChange(of: widgetDrawingPresented.wrappedValue) { _, isPresented in
                    if !isPresented, dependencies.widgetDrawingViewModel?.hasSentDrawing == true {
                        actions.sentSomethingToPartner(.drawing)
                    }
                }
        }
    }

    private var pairedHome: some View {
        PairedHomeView(
            currentUserID: identity.currentUserID,
            coupleID: identity.coupleID,
            currentDisplayName: identity.currentDisplayName,
            currentProfilePhotoAssetID: identity.currentProfilePhotoAssetID,
            partnerDisplayName: identity.partnerDisplayName,
            partnerProfilePhotoAssetID: identity.partnerProfilePhotoAssetID,
            accessNotice: identity.accessNotice,
            relationshipStartedOn: milestoneViewModel.startedOn,
            milestoneIsSaving: milestoneViewModel.isSaving,
            milestoneIsLoading: !milestoneViewModel.isPresentationReady || !coupleDatesViewModel.hasLoaded,
            onSaveRelationshipStartedOn: { date in
                await milestoneViewModel.save(startedOn: date)
            },
            coupleDates: coupleDatesViewModel,
            coupleDateNames: CoupleDateNames(
                currentUserID: identity.currentUserID,
                partnerUserID: identity.partnerUserID,
                partnerName: dailyChallengeParticipants.partnerName
            ),
            dailyChallengeCardState: dailyChallengeViewModel.homeCardState,
            dailyChallengeStreak: StreakPillState(dailyChallengeViewModel.streak),
            zoomNamespace: zoomNamespace,
            locationMapState: locationMapState,
            mapTiles: models.mapTiles,
            onPromptCurrentLocation: {
                Task { await actions.shareLocation() }
            },
            onPauseLocationSharing: { end in
                Task { await locationViewModel.pauseSharing(until: end) }
            },
            // Topic chats stay off Home. The Topics card says when one has a new message.
            unreadChats: dailyChallengeViewModel.unreadDailyChats.map { summary in
                UnreadChatRow(
                    id: summary.subject.id,
                    prompt: dailyChallengeViewModel.questionPrompt(for: summary.subject.id),
                    preview: summary.lastMessagePreview
                )
            },
            onOpenChat: startOpeningDailyChat(questionID:),
            games: gamesViewModel,
            hearts: heartsViewModel,
            onOpenGame: openGameFromHome,
            onTapStreak: openStreakDetails,
            onOpenDailyChallenge: openDailyChallengeFromHome,
            onOpenPartnerQuestion: openPartnerQuestionFromHome,
            firstSteps: firstSteps,
            onOpenFirstStep: openFirstStep,
            onCloseFirstSteps: closeFirstSteps,
            onOpenWidgetDrawing: actions.openWidgetDrawing,
            lookBack: lookBackViewModel,
            onOpenLookBack: openLookBack,
            stories: storiesViewModel,
            storyPeople: storyPeople,
            mail: mailViewModel,
            memories: memoriesViewModel,
            onRefresh: {
                await refreshDailyChallenge()
                await actions.refreshHome()
            }
        ).onOpenSavedMemory(openSavedVisitMemory)
    }

    private var questionsTab: some View {
        NavigationStack(path: $questionsPath) {
            questionsContent
                .searchToolbarButton(action: openSearch)
                .analyticsScreen("questions")
                .navigationDestination(for: QuestionsDestination.self, destination: questionsDestination)
                .navigationDestination(item: $gameChatDestination) { destination in
                    ThreadChatScreen(viewModel: destination.viewModel)
                        .id(destination.id)
                }
        }
    }

    private var questionsContent: some View {
        DailyChallengeScreen(
            viewModel: dailyChallengeViewModel,
            zoomNamespace: zoomNamespace,
            focusedQuestionIDs: $focusedDailyQuestionIDs,
            chatQuestion: $dailyChatQuestion,
            requestedConversationID: $requestedConversationID,
            isCoupleChatRequested: $isCoupleChatRequested,
            onOpenAnswerFlow: { openAnswerFlow(source: .questions) },
            onTapStreak: openStreakDetails,
            onRefresh: {
                await refreshDailyChallenge()
            },
            onAnswerPartnerQuestion: openPartnerAnswerFlow,
            privacySafetyService: dependencies.settingsPrivacyService,
            privacyOperationProvider: dependencies.settingsPrivacyOperationProvider,
            onReportedAndLeft: actions.leftRelationship,
            conversations: chatSummaries.conversations(
                memories: memoriesViewModel.timeline.flatMap(\.memories),
                stories: storiesViewModel.stories
            ),
            storyPeople: storyPeople,
            stories: storiesViewModel,
            topicsCard: questionsTopicsCard,
            coupleID: identity.coupleID,
            partnerGameKinds: Set(gamesViewModel.partnerGameKinds)
        )
    }

    /// The Topics card on the Questions tab, and the topic questions that join its list.
    private var questionsTopicsCard: TopicsCardContent {
        TopicsCardContent(
            topics: topicsViewModel.cardTopics,
            hook: topicsHook,
            isShown: !topicsViewModel.hasLoadedOverview || !topicsViewModel.overview.isEmpty,
            onOpen: openTopics,
            shelfTopics: topicsViewModel.overview,
            newQuestionCount: topicsViewModel.newQuestionCount(for:),
            onOpenTopic: { questionsPath.append(.topic($0)) },
            waitingQuestions: topicsViewModel.waitingQuestions,
            topicTitles: topicsViewModel.titlesByKey
        )
    }

    private var settingsTab: some View {
        NavigationStack {
            settingsView
                .searchToolbarButton(action: openSearch)
                .analyticsScreen("settings")
        }
    }

    private var settingsView: some View {
        SettingsView(
            viewModel: models.settings(userID: identity.currentUserID),
            currentUserID: identity.currentUserID,
            currentDisplayName: identity.currentDisplayName,
            currentCustomProfilePhotoAssetID: identity.currentCustomProfilePhotoAssetID,
            currentProviderProfilePhotoAssetID: identity.currentProviderProfilePhotoAssetID,
            partnerUserID: identity.partnerUserID,
            partner: identity.partnerName,
            partnerProfilePhotoAssetID: identity.partnerProfilePhotoAssetID,
            relationshipStartedOn: milestoneViewModel.startedOn,
            milestoneIsSaving: milestoneViewModel.isSaving,
            onSaveRelationshipStartedOn: { date in
                await milestoneViewModel.save(startedOn: date)
            },
            coupleDates: coupleDatesViewModel,
            locationViewModel: locationViewModel,
            partnerName: dailyChallengeParticipants.partnerName,
            ownAccess: identity.ownAccess,
            onLeftRelationship: actions.leftRelationship,
            onLogout: actions.logOut,
            onDeleteAccount: actions.deleteAccount,
            isLoggingOut: actions.isLoggingOut,
            onUpdateProfile: { [updateProfile = actions.updateProfile] displayName, photoUpdate in
                await updateProfile(displayName, photoUpdate)
            },
            onPurchasesRestored: { [purchasesRestored = actions.purchasesRestored] in
                await purchasesRestored()
            },
            loadMarkEditor: { [gamesViewModel] in await gamesViewModel.makeMarkEditor() },
            privacySafetyService: dependencies.settingsPrivacyService,
            privacyOperationProvider: dependencies.settingsPrivacyOperationProvider
        )
    }
}

/// What the Us tab badge counts from. A change restarts `refreshStoryBadge()`.
struct StoryBadgeKey: Equatable {
    let stories: [Story]
    let partner: UUID?
}

/// SwiftUI tells only a tab's content where the tab bar sits, so each tab passes it up.
/// A tab that has no placement, such as one not on screen, leaves the last one in place.
private struct TabBarPlacementReporter: ViewModifier {
    let report: (TabBarPlacement) -> Void
    @Environment(\.tabBarPlacement) private var placement

    func body(content: Content) -> some View {
        content.onChange(of: placement, initial: true) { _, placement in
            if let placement { report(placement) }
        }
    }
}
