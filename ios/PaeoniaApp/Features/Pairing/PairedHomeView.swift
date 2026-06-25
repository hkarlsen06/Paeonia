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
        VStack(spacing: 0) {
            PairedProfilesHeader(
                currentName: currentName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerName: partnerName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID
            )
            .frame(maxWidth: .infinity)

            Spacer(minLength: PaeoniaSpacing.space32)

            HomeWidgetCard(onOpen: onOpenWidgetDrawing)

            Spacer(minLength: PaeoniaSpacing.space32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space16)
        .background(.paeoniaBackgroundPrimary)
    }
    .preferredColorScheme(.dark)
}
