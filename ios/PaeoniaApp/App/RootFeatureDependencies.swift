import Foundation

/// Optional feature-level dependencies owned by the root composition boundary.
///
/// Production uses the empty value, so every feature creates its normal live
/// dependency. Debug local flows and focused integration tests inject deterministic
/// view models here while still rendering the production root and feature views.
struct RootFeatureDependencies {
    var paywallViewModel: PaywallViewModel?
    var paywallPresentationOverride: PaywallPresentationOverride?
    var pairingInviteViewModel: PairingInviteViewModel?
    var inviterFirstDayModel: InviterFirstDayModel?
    var pairingJoinViewModel: PairingJoinViewModel?
    var dailyChallengeViewModel: DailyChallengeViewModel?
    var milestoneViewModel: RelationshipMilestoneViewModel?
    var memoriesViewModel: MemoriesViewModel?
    var gamesViewModel: GamesViewModel?
    var visitsViewModel: VisitsViewModel?
    var settingsViewModel: SettingsViewModel?
    var avatarStylingModel: AvatarStylingModel?
    var storiesViewModel: StoriesViewModel?
    var homeMapTiles: HomeMapTileStatus?
    var settingsPrivacyService: (any PrivacySafetyServicing)?
    var settingsPrivacyOperationProvider: (any SyncClientOperationProviding)?
    var widgetDrawingViewModel: WidgetDrawingViewModel?
    var widgetHistoryViewModel: WidgetDrawingHistoryViewModel?
    var widgetHistoryThumbnailLoader: (any WidgetRevisionThumbnailLoading)?

    init(
        paywallViewModel: PaywallViewModel? = nil,
        paywallPresentationOverride: PaywallPresentationOverride? = nil,
        pairingInviteViewModel: PairingInviteViewModel? = nil,
        inviterFirstDayModel: InviterFirstDayModel? = nil,
        pairingJoinViewModel: PairingJoinViewModel? = nil,
        dailyChallengeViewModel: DailyChallengeViewModel? = nil,
        milestoneViewModel: RelationshipMilestoneViewModel? = nil,
        memoriesViewModel: MemoriesViewModel? = nil,
        gamesViewModel: GamesViewModel? = nil,
        visitsViewModel: VisitsViewModel? = nil,
        settingsViewModel: SettingsViewModel? = nil,
        avatarStylingModel: AvatarStylingModel? = nil,
        storiesViewModel: StoriesViewModel? = nil,
        homeMapTiles: HomeMapTileStatus? = nil,
        settingsPrivacyService: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        settingsPrivacyOperationProvider: (any SyncClientOperationProviding)? = nil,
        widgetDrawingViewModel: WidgetDrawingViewModel? = nil,
        widgetHistoryViewModel: WidgetDrawingHistoryViewModel? = nil,
        widgetHistoryThumbnailLoader: (any WidgetRevisionThumbnailLoading)? = nil
    ) {
        self.paywallViewModel = paywallViewModel
        self.paywallPresentationOverride = paywallPresentationOverride
        self.pairingInviteViewModel = pairingInviteViewModel
        self.inviterFirstDayModel = inviterFirstDayModel
        self.pairingJoinViewModel = pairingJoinViewModel
        self.dailyChallengeViewModel = dailyChallengeViewModel
        self.milestoneViewModel = milestoneViewModel
        self.memoriesViewModel = memoriesViewModel
        self.gamesViewModel = gamesViewModel
        self.visitsViewModel = visitsViewModel
        self.settingsViewModel = settingsViewModel
        self.avatarStylingModel = avatarStylingModel
        self.storiesViewModel = storiesViewModel
        self.homeMapTiles = homeMapTiles
        self.settingsPrivacyService = settingsPrivacyService
        self.settingsPrivacyOperationProvider = settingsPrivacyOperationProvider
        self.widgetDrawingViewModel = widgetDrawingViewModel
        self.widgetHistoryViewModel = widgetHistoryViewModel
        self.widgetHistoryThumbnailLoader = widgetHistoryThumbnailLoader
    }
}
