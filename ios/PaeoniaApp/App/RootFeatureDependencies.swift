import Foundation

/// Optional feature-level dependencies owned by the root composition boundary.
///
/// Production uses the empty value, so every feature creates its normal live
/// dependency. Debug local flows and focused integration tests inject deterministic
/// view models here while still rendering the production root and feature views.
@MainActor
struct RootFeatureDependencies {
    var paywallViewModel: PaywallViewModel?
    var paywallPresentationOverride: PaywallPresentationOverride?
    var pairingInviteViewModel: PairingInviteViewModel?
    var dailyChallengeViewModel: DailyChallengeViewModel?
    var milestoneViewModel: RelationshipMilestoneViewModel?
    var memoriesViewModel: MemoriesViewModel?
    var settingsViewModel: SettingsViewModel?
    var settingsPrivacyService: (any PrivacySafetyServicing)?
    var settingsPrivacyOperationProvider: (any SyncClientOperationProviding)?
    var widgetDrawingViewModel: WidgetDrawingViewModel?
    var widgetHistoryViewModel: WidgetDrawingHistoryViewModel?
    var widgetHistoryThumbnailLoader: (any WidgetRevisionThumbnailLoading)?

    init(
        paywallViewModel: PaywallViewModel? = nil,
        paywallPresentationOverride: PaywallPresentationOverride? = nil,
        pairingInviteViewModel: PairingInviteViewModel? = nil,
        dailyChallengeViewModel: DailyChallengeViewModel? = nil,
        milestoneViewModel: RelationshipMilestoneViewModel? = nil,
        memoriesViewModel: MemoriesViewModel? = nil,
        settingsViewModel: SettingsViewModel? = nil,
        settingsPrivacyService: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        settingsPrivacyOperationProvider: (any SyncClientOperationProviding)? = nil,
        widgetDrawingViewModel: WidgetDrawingViewModel? = nil,
        widgetHistoryViewModel: WidgetDrawingHistoryViewModel? = nil,
        widgetHistoryThumbnailLoader: (any WidgetRevisionThumbnailLoading)? = nil
    ) {
        self.paywallViewModel = paywallViewModel
        self.paywallPresentationOverride = paywallPresentationOverride
        self.pairingInviteViewModel = pairingInviteViewModel
        self.dailyChallengeViewModel = dailyChallengeViewModel
        self.milestoneViewModel = milestoneViewModel
        self.memoriesViewModel = memoriesViewModel
        self.settingsViewModel = settingsViewModel
        self.settingsPrivacyService = settingsPrivacyService
        self.settingsPrivacyOperationProvider = settingsPrivacyOperationProvider
        self.widgetDrawingViewModel = widgetDrawingViewModel
        self.widgetHistoryViewModel = widgetHistoryViewModel
        self.widgetHistoryThumbnailLoader = widgetHistoryThumbnailLoader
    }
}
