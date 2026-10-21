import SwiftUI

/// The five tabs and the views they show.
extension MainTabView {
    @ViewBuilder
    func content(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            homeTab
        case .questions:
            questionsTab
        case .games:
            gamesTab
        case .us:
            usTab
        case .memories:
            memoriesTab
        }
    }

    func badgeCount(for tab: MainTab) -> Int {
        switch tab {
        case .questions: dailyChallengeViewModel.unreadChats.count
        case .games: gamesViewModel.isYourTurn ? 1 : 0
        case .memories: chatSummaries.unreadCount(of: .memory)
        case .home:
            StoryTimeline.unseenCount(storiesViewModel.stories, partner: identity.partnerUserID, at: storyBadgeDate)
        case .us: 0
        }
    }

    private var gamesTab: some View {
        GamesRootView(viewModel: gamesViewModel, path: $gamesPath)
    }

    var gamesParticipants: GameParticipants {
        GameParticipants(
            currentUserID: identity.currentUserID,
            coupleID: identity.coupleID,
            partnerName: dailyChallengeParticipants.partnerName,
            currentName: identity.currentDisplayName ?? String(localized: .dailyChallengeChoiceYou),
            currentPhotoAssetID: identity.currentProfilePhotoAssetID,
            partnerPhotoAssetID: identity.partnerProfilePhotoAssetID
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

    /// Counts the Home tab badge again now, then again each time an unseen story
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
                coupleID: identity.coupleID,
                viewModel: memoriesViewModel,
                stories: storiesViewModel,
                storyPeople: storyPeople,
                gameRounds: gamesViewModel.guessMySpot.history,
                onLocalChange: actions.syncAfterLocalChange
            )
            .searchToolbarButton(action: openSearch)
            .analyticsScreen("memories")
        }
    }

    private var homeTab: some View {
        NavigationStack {
            // Home hides its navigation bar and draws the brand mark and streak in its
            // own header. Screens pushed from it keep their bar.
            pairedHome
                // Shows only where Home has a navigation bar, on a wide iPad.
                .searchToolbarButton(placement: .topBarTrailing, action: openSearch)
                .analyticsScreen("home")
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
                .lookBackDrawingHistory(isPresented: $isLookBackDrawingHistoryPresented, dependencies: dependencies)
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
            relationshipStartedOn: milestoneViewModel.startedOn,
            milestoneIsSaving: milestoneViewModel.isSaving,
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
            onOpenWidgetDrawing: actions.openWidgetDrawing,
            lookBack: lookBackViewModel,
            onOpenLookBack: openLookBack,
            stories: storiesViewModel,
            storyPeople: storyPeople,
            onRefresh: {
                await refreshDailyChallenge()
                await actions.refreshHome()
            }
        )
    }

    private var questionsTab: some View {
        NavigationStack(path: $questionsPath) {
            DailyChallengeScreen(
                viewModel: dailyChallengeViewModel,
                zoomNamespace: zoomNamespace,
                focusedQuestionIDs: $focusedDailyQuestionIDs,
                chatQuestion: $dailyChatQuestion,
                onOpenAnswerFlow: { openAnswerFlow(source: .questions) },
                onTapStreak: openStreakDetails,
                onRefresh: {
                    await refreshDailyChallenge()
                },
                onAnswerPartnerQuestion: openPartnerAnswerFlow,
                privacySafetyService: dependencies.settingsPrivacyService,
                privacyOperationProvider: dependencies.settingsPrivacyOperationProvider,
                onReportedAndLeft: actions.leftRelationship,
                topicsCard: TopicsCardContent(
                    topics: topicsViewModel.cardTopics,
                    hook: topicsHook,
                    isShown: topicsViewModel.hasLoadedOverview && !topicsViewModel.overview.isEmpty,
                    onOpen: openTopics
                )
            )
            .searchToolbarButton(action: openSearch)
            .analyticsScreen("questions")
            .navigationDestination(for: QuestionsDestination.self, destination: questionsDestination)
        }
    }

    private var usTab: some View {
        NavigationStack {
            settingsView
                .searchToolbarButton(action: openSearch)
                .analyticsScreen("us")
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

/// What the Home tab badge counts from. A change restarts `refreshStoryBadge()`.
struct StoryBadgeKey: Equatable {
    let stories: [Story]
    let partner: UUID?
}
