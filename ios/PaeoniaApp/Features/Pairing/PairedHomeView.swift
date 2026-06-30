import SwiftUI

struct PairedHomeView: View {
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    let dailyChallengeCardState: DailyChallengeCardState
    let dailyChallengeStreak: StreakPillState
    let zoomNamespace: Namespace.ID?
    let locationMapState: CoupleMapState
    let onPromptCurrentLocation: () -> Void
    var onTapStreak: (() -> Void)?
    var onOpenDailyChallenge: () -> Void = {}
    var onOpenWidgetDrawing: () -> Void = {}
    var onRefresh: () async -> Void = {}
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID? = nil,
        dailyChallengeCardState: DailyChallengeCardState = DailyChallengeCardState(
            kind: .loading,
            answeredCount: 0,
            totalCount: DailyChallengeProgress.requiredOwnQuestionCount
        ),
        dailyChallengeStreak: StreakPillState = .hidden,
        zoomNamespace: Namespace.ID? = nil,
        locationMapState: CoupleMapState,
        onPromptCurrentLocation: @escaping () -> Void = {},
        onTapStreak: (() -> Void)? = nil,
        onOpenDailyChallenge: @escaping () -> Void = {},
        onOpenWidgetDrawing: @escaping () -> Void = {},
        onRefresh: @escaping () async -> Void = {}
    ) {
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.dailyChallengeCardState = dailyChallengeCardState
        self.dailyChallengeStreak = dailyChallengeStreak
        self.zoomNamespace = zoomNamespace
        self.locationMapState = locationMapState
        self.onPromptCurrentLocation = onPromptCurrentLocation
        self.onTapStreak = onTapStreak
        self.onOpenDailyChallenge = onOpenDailyChallenge
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
                    MilestoneCountdownCard()

                    HomeWidgetCard(onOpen: onOpenWidgetDrawing)
                }

                dailyPromptCard

                CoupleMapCard(
                    currentName: currentName,
                    currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                    partnerName: partnerName,
                    partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                    state: locationMapState,
                    onPromptCurrentLocation: onPromptCurrentLocation
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space12)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
        .scrollIndicators(.hidden)
        .refreshable { await onRefresh() }
        // The home screen shows the couple's current widget, so seeing it means
        // the user has noticed any update — clear lingering partner alerts.
        .task {
            await WidgetUpdateNotifications.clearDelivered()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await WidgetUpdateNotifications.clearDelivered() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the scroll view reach the bottom edge so the tab bar's automatic
        // content inset applies and cards scroll behind the floating glass bar,
        // instead of a flat background panel filling the space above it.
        .background(.paeoniaBackgroundPrimary)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image(.paeoniaMark)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .accessibilityHidden(true)
            }
            // The mark is the brand, not a control, so keep it free of the
            // system's Liquid Glass capsule and let it sit flat on the bar.
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .principal) {
                PairedProfilesHeader(
                    currentName: currentName,
                    currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                    partnerName: partnerName,
                    partnerProfilePhotoAssetID: partnerProfilePhotoAssetID
                )
                .padding(.top, PaeoniaSpacing.space2)
            }

            // The streak lives at the trailing edge of the bar, sized to match the brand
            // mark and carried in the toolbar's standard background. It fades in when
            // the streak count becomes available rather than popping in abruptly.
            // Reserving a fixed-width placeholder slot in the toolbar is not idiomatic
            // SwiftUI, so we keep the conditional item and rely on an opacity transition
            // instead. Instant under Reduce Motion.
            if dailyChallengeStreak.isVisible {
                ToolbarItem(placement: .topBarTrailing) {
                    DailyStreakToolbarLabel(state: dailyChallengeStreak, onTap: onTapStreak)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: dailyChallengeStreak.isVisible)
                }
            }
        }
    }

    private var dailyPromptCard: some View {
        DailyPromptCard(
            state: dailyChallengeCardState,
            partnerName: partnerName,
            prefersPartnerAnswersWhenComplete: true,
            onAnswer: onOpenDailyChallenge
        )
        .zoomSource(DailyFlowZoom.home, in: zoomNamespace)
    }

    private var currentName: String {
        currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName)
    }

    private var partnerName: String {
        partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }
}

#Preview {
    NavigationStack {
        PairedHomeView(
            currentDisplayName: "Hjalmar",
            partnerDisplayName: "Oda",
            locationMapState: .partnerUnknown(.notSharing)
        )
    }
    .preferredColorScheme(.dark)
}
