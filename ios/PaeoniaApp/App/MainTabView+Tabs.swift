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
        case .home, .us, .memories: 0
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

    private var memoriesTab: some View {
        NavigationStack(path: $memoriesPath) {
            MemoriesScreen(
                currentUserID: identity.currentUserID,
                coupleID: identity.coupleID,
                viewModel: memoriesViewModel,
                stories: storiesViewModel,
                storyPeople: storyPeople,
                onLocalChange: actions.syncAfterLocalChange
            )
        }
    }

    private var homeTab: some View {
        NavigationStack {
            pairedHome
                .navigationBarTitleDisplayMode(.inline)
                // The brand mark and streak are populated into the navigation bar
                // from inside PairedHomeView.
                .navigationDestination(isPresented: widgetDrawingPresented) {
                    WidgetDrawingView(
                        ownerUserID: identity.currentUserID,
                        coupleID: identity.coupleID,
                        authorName: identity.currentDisplayName,
                        viewModel: dependencies.widgetDrawingViewModel,
                        historyViewModel: dependencies.widgetHistoryViewModel,
                        historyThumbnailLoader: dependencies.widgetHistoryThumbnailLoader
                    )
                }
                .lookBackDrawingHistory(isPresented: $isLookBackDrawingHistoryPresented, dependencies: dependencies)
                .onChange(of: widgetDrawingPresented.wrappedValue) { _, isPresented in
                    if !isPresented, dependencies.widgetDrawingViewModel?.hasSentDrawing == true {
                        actions.sentSomethingToPartner()
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
            unreadChats: dailyChallengeViewModel.unreadChats.map { summary in
                UnreadChatRow(
                    id: summary.questionID,
                    prompt: dailyChallengeViewModel.questionPrompt(for: summary.questionID),
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
        NavigationStack {
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
                onReportedAndLeft: actions.leftRelationship
            )
        }
    }

    private var usTab: some View {
        NavigationStack {
            settingsView
        }
    }

    private var settingsView: some View {
        SettingsView(
            viewModel: models.settings(userID: identity.currentUserID),
            currentUserID: identity.currentUserID,
            currentDisplayName: identity.currentDisplayName,
            currentCustomProfilePhotoAssetID: identity.currentCustomProfilePhotoAssetID,
            currentProviderProfilePhotoAssetID: identity.currentProviderProfilePhotoAssetID,
            currentAuthProvider: identity.currentAuthProvider,
            partnerUserID: identity.partnerUserID,
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
