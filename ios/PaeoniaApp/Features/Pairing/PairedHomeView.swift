import SwiftUI

struct PairedHomeView: View {
    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    var onOpenWidgetDrawing: () -> Void = {}

    init(
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerDisplayName: String?,
        partnerProfilePhotoAssetID: UUID? = nil,
        onOpenWidgetDrawing: @escaping () -> Void = {}
    ) {
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.onOpenWidgetDrawing = onOpenWidgetDrawing
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                MilestoneCountdownCard()

                DailyPromptCard()

                HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
                    CoupleMapCard(
                        currentName: currentName,
                        currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                        partnerName: partnerName,
                        partnerProfilePhotoAssetID: partnerProfilePhotoAssetID
                    )

                    HomeWidgetCard(onOpen: onOpenWidgetDrawing)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space12)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
        .scrollIndicators(.hidden)
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
        }
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
            partnerDisplayName: "Oda"
        )
    }
    .preferredColorScheme(.dark)
}
