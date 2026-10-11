import SwiftUI

/// Who is signed in and who they are paired with, as the tabs need it.
struct MainTabIdentity: Equatable {
    var currentUserID: UUID?
    var currentDisplayName: String?
    var currentProfilePhotoAssetID: UUID?
    var currentCustomProfilePhotoAssetID: UUID?
    var currentProviderProfilePhotoAssetID: UUID?
    var currentAuthProvider: AuthProvider?
    var partnerUserID: UUID?
    var partnerDisplayName: String?
    var partnerProfilePhotoAssetID: UUID?
    /// The active couple, needed to create new memories. Cosmetic for the rest of the
    /// tabs, so it must not be part of any load-bearing `.task(id:)` key.
    var coupleID: UUID?
    /// The day the relationship started (`yyyy-MM-dd`), used by the Us-tab milestone
    /// countdown. Display-only, so it never keys a load.
    var relationshipStartedOn: String?
}

/// Root-owned work the tabs ask for.
struct MainTabActions {
    var openWidgetDrawing: () -> Void = {}
    /// Pull-to-refresh on Home, after the daily challenge refresh.
    var refreshHome: () async -> Void = {}
    /// Runs one sync pass so a daily challenge refresh sees partner answers.
    var refreshDailyChallenge: () async -> Void = {}
    /// Sends local changes (answers, memories, start date) now.
    var syncAfterLocalChange: @MainActor @Sendable () async -> Void = {}
    /// The user unpaired, so the root resolves access again.
    var leftRelationship: () -> Void = {}
    var logOut: () -> Void = {}
    /// True while a log-out runs, so the log-out row shows progress.
    var isLoggingOut = false
    /// Runs after the paired Settings confirmation. Auth/session lifecycle
    /// stays rooted rather than being duplicated in the Settings view model.
    var deleteAccount: () -> Void = {}
    /// Saves the paired user's canonical profile through the root-owned auth
    /// service so every tab receives the resulting session in one update.
    var updateProfile: @MainActor @Sendable (String, AuthProfilePhotoUpdate) async -> Bool = { _, _ in false }
    /// Re-resolves entitlement/access after StoreKit has re-confirmed a purchase.
    var purchasesRestored: @MainActor @Sendable () async -> Void = {}
}

/// The tabs' long-lived view models. `MainTabView` keeps one in `@State`, and
/// the models are built on first use. A SwiftUI view initializer runs on every
/// parent update, so building them there would make and throw away three view
/// models each time.
@MainActor
final class MainTabModels {
    private let dependencies: RootFeatureDependencies

    init(dependencies: RootFeatureDependencies) {
        self.dependencies = dependencies
    }

    lazy var dailyChallenge: DailyChallengeViewModel =
        dependencies.dailyChallengeViewModel ?? DailyChallengeViewModel()
    lazy var milestone: RelationshipMilestoneViewModel =
        dependencies.milestoneViewModel ?? RelationshipMilestoneViewModel()
    lazy var memories: MemoriesViewModel =
        dependencies.memoriesViewModel ?? MemoriesViewModel()
}

/// The native tab bar shown once a couple is paired.
///
/// Tab selection is owned by `RootViewModel` and passed in as a binding. That lets
/// navigation intent, such as opening the widget drawing screen from the Home
/// Screen widget, select the Home tab and present its destination in one atomic
/// update, so the screen can never open hidden behind another tab. Deep links,
/// the daily answer flows, and the streak sheets live in `MainTabView+Flows.swift`.
struct MainTabView: View {
    let tabs: [MainTab]
    let identity: MainTabIdentity
    let locationMapState: CoupleMapState
    let locationViewModel: LocationMapViewModel
    let selection: Binding<MainTab>
    let widgetDrawingPresented: Binding<Bool>
    let deepLink: Binding<PaeoniaDeepLink?>
    let actions: MainTabActions
    let dependencies: RootFeatureDependencies

    @State var models: MainTabModels
    @State var isAnswerFlowPresented = false
    /// Which card the daily answer flow should zoom out of (the Home prompt card or the
    /// Questions-tab hero card), so the cover grows from the one the user tapped.
    @State var dailyFlowSource: DailyFlowSource = .home
    /// Streak-restore offer opened from the streak badge when a lost streak can still
    /// be bought back, outside the answer flow.
    @State var showStreakRestore = false
    /// Read-only streak detail sheet, opened by tapping the streak badge while the
    /// streak is healthy (nothing to restore).
    @State var showStreakDetail = false
    /// The Questions-tab single-question partner-answer flow. The tapped question drives
    /// presentation and is the card the cover zooms out of.
    @State var partnerAnswerQuestion: DailyChallengeQuestion?
    /// Question to scroll to and briefly highlight after a notification deep link.
    @State var focusedDailyQuestionID: UUID?
    @State var dailyChatQuestion: DailyChallengeQuestion?
    @Namespace var zoomNamespace
    @Environment(PaeoniaBannerCenter.self) var bannerCenter
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(
        tabs: [MainTab] = MainTab.allCases,
        identity: MainTabIdentity,
        locationMapState: CoupleMapState,
        locationViewModel: LocationMapViewModel,
        selection: Binding<MainTab>,
        widgetDrawingPresented: Binding<Bool>,
        deepLink: Binding<PaeoniaDeepLink?> = .constant(nil),
        actions: MainTabActions = MainTabActions(),
        dependencies: RootFeatureDependencies? = nil
    ) {
        let dependencies = dependencies ?? RootFeatureDependencies()
        self.tabs = tabs
        self.identity = identity
        self.locationMapState = locationMapState
        self.locationViewModel = locationViewModel
        self.selection = selection
        self.widgetDrawingPresented = widgetDrawingPresented
        self.deepLink = deepLink
        self.actions = actions
        self.dependencies = dependencies
        _models = State(initialValue: MainTabModels(dependencies: dependencies))
    }

    var dailyChallengeViewModel: DailyChallengeViewModel { models.dailyChallenge }
    var milestoneViewModel: RelationshipMilestoneViewModel { models.milestone }
    var memoriesViewModel: MemoriesViewModel { models.memories }

    var body: some View {
        presentingDailyFlows(on: tabContent)
    }

    private var tabContent: some View {
        TabView(selection: selection) {
            ForEach(tabs) { tab in
                content(for: tab)
                    .tag(tab)
                    .badge(tab == .questions ? dailyChallengeViewModel.unreadChats.count : 0)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.systemImage)
                        }
                        .accessibilityIdentifier("mainTab.\(tab.rawValue)")
                    }
            }
        }
        .tint(.paeoniaAccentPrimary)
        // Key the load on the signed-in user alone. The partner id, display names,
        // and profile photos all populate/refresh shortly after launch; if they were
        // in this id, every one of those changes would cancel and restart the task,
        // killing an in-flight question fetch with URLError.cancelled. Cosmetic
        // identity instead flows through refreshParticipants below, which never
        // reloads. See the `.task(id:)` note in AGENTS.md.
        .task(id: identity.currentUserID) {
            dailyChallengeViewModel.setLocalChangeSyncHandler(actions.syncAfterLocalChange)
            await dailyChallengeViewModel.configure(participants: dailyChallengeParticipants)
        }
        .onChange(of: dailyChallengeParticipants) { _, participants in
            dailyChallengeViewModel.refreshParticipants(participants)
        }
        .task(id: identity.currentUserID) {
            milestoneViewModel.setSyncAfterLocalChange(actions.syncAfterLocalChange)
            await milestoneViewModel.configure(
                ownerUserID: identity.currentUserID,
                serverStartedOn: identity.relationshipStartedOn
            )
        }
        .onChange(of: identity.relationshipStartedOn) { _, startedOn in
            milestoneViewModel.refreshServerStartedOn(startedOn)
        }
        .onChange(of: milestoneViewModel.error) { _, error in
            guard let error else { return }
            bannerCenter.show(.error(message: error.message))
            milestoneViewModel.clearError()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await milestoneViewModel.retryPendingChangeIfNeeded() }
            }
        }
        .task(id: deepLink.wrappedValue) {
            await handleDeepLink(deepLink.wrappedValue)
        }
    }

    /// Both partners' identity, used by the daily challenge to label partner-choice
    /// answers. A change of signed-in user reloads; a partner name change just
    /// relabels.
    var dailyChallengeParticipants: DailyChallengeParticipants {
        DailyChallengeParticipants(
            currentUserID: identity.currentUserID,
            currentDisplayName: identity.currentDisplayName,
            currentProfilePhotoAssetID: identity.currentProfilePhotoAssetID,
            partnerUserID: identity.partnerUserID,
            partnerDisplayName: identity.partnerDisplayName,
            partnerProfilePhotoAssetID: identity.partnerProfilePhotoAssetID
        )
    }

    @ViewBuilder
    private func content(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            homeTab
        case .questions:
            questionsTab
        case .you:
            youTab
        case .memories:
            memoriesTab
        }
    }

    private var memoriesTab: some View {
        NavigationStack {
            MemoriesScreen(
                currentUserID: identity.currentUserID,
                coupleID: identity.coupleID,
                viewModel: memoriesViewModel,
                onLocalChange: actions.syncAfterLocalChange
            )
        }
    }

    private var homeTab: some View {
        NavigationStack {
            pairedHome
                .navigationBarTitleDisplayMode(.inline)
                // The brand mark and couple avatars are populated into the navigation
                // bar from inside PairedHomeView, where the name/photo data lives.
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
            dailyChallengeCardState: dailyChallengeViewModel.homeCardState,
            dailyChallengeStreak: StreakPillState(dailyChallengeViewModel.streak),
            zoomNamespace: zoomNamespace,
            locationMapState: locationMapState,
            onPromptCurrentLocation: {
                Task { await locationViewModel.promptForCurrentLocation() }
            },
            unreadChats: dailyChallengeViewModel.unreadChats.map { summary in
                UnreadChatRow(
                    id: summary.instanceID,
                    prompt: dailyChallengeViewModel.questionPrompt(for: summary.instanceID),
                    preview: summary.lastMessagePreview
                )
            },
            onOpenChat: { instanceID in
                Task { await openDailyChat(instanceID: instanceID) }
            },
            onTapStreak: openStreakDetails,
            onOpenDailyChallenge: openDailyChallengeFromHome,
            onOpenWidgetDrawing: actions.openWidgetDrawing,
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
                focusedQuestionID: $focusedDailyQuestionID,
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

    private var youTab: some View {
        NavigationStack {
            SettingsView(
                viewModel: dependencies.settingsViewModel,
                currentUserID: identity.currentUserID,
                currentDisplayName: identity.currentDisplayName,
                currentCustomProfilePhotoAssetID: identity.currentCustomProfilePhotoAssetID,
                currentProviderProfilePhotoAssetID: identity.currentProviderProfilePhotoAssetID,
                currentAuthProvider: identity.currentAuthProvider,
                partnerUserID: identity.partnerUserID,
                relationshipStartedOn: milestoneViewModel.startedOn,
                milestoneIsSaving: milestoneViewModel.isSaving,
                onSaveRelationshipStartedOn: { date in
                    await milestoneViewModel.save(startedOn: date)
                },
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
                privacySafetyService: dependencies.settingsPrivacyService,
                privacyOperationProvider: dependencies.settingsPrivacyOperationProvider
            )
        }
    }
}

#if DEBUG
#Preview {
    MainTabView(
        identity: MainTabIdentity(
            currentUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
            currentDisplayName: "Hjalmar",
            partnerUserID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            partnerDisplayName: "Oda",
            coupleID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
            relationshipStartedOn: "2026-01-08"
        ),
        locationMapState: .partnerUnknown(.notSharing),
        locationViewModel: LocationMapViewModel(),
        selection: .constant(.home),
        widgetDrawingPresented: .constant(false)
    )
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
