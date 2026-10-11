import SwiftUI

/// The settled "two people linked by a heart" element, reused at the top of the
/// paired Home tab: each person's avatar, their names, and the beating-heart
/// connector between them. This is the same arrangement that lands at the end of
/// the pairing celebration.
///
/// Profile photos load the same way the celebration loads them, falling back to
/// initials while they load or when none is set. VoiceOver reads the whole header
/// as one element, for example "You and Oda".
struct PairedProfilesHeader: View {
    private static let coordinateSpace = "pairedProfilesHeader"

    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    private let profilePhotoProvider: (any ProfilePhotoImageProviding)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentPhoto = PairingProfilePhoto()
    @State private var partnerPhoto = PairingProfilePhoto()

    init(
        currentName: String,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerName: String,
        partnerProfilePhotoAssetID: UUID? = nil,
        profilePhotoProvider: (any ProfilePhotoImageProviding)? = nil
    ) {
        self.currentName = currentName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerName = partnerName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.profilePhotoProvider = profilePhotoProvider ?? ProfilePhotoImageProviderFactory.shared
    }

    var body: some View {
        PairingCelebrationProfilesView(
            currentName: currentName,
            currentPhoto: currentPhoto.image,
            partnerName: partnerName,
            partnerPhoto: partnerPhoto.image,
            partnerSlotIsPlaceholder: false,
            surroundingsOpacity: 1,
            slotCoordinateSpace: Self.coordinateSpace,
            metrics: .compact,
            onPartnerSlotChange: { _ in }
        )
        // Crossfade between initials and photo, and between different photos on
        // reload. Keyed on the decoded image, so it animates only when a photo
        // actually changes, not on every render.
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: currentPhoto.imageID)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: partnerPhoto.imageID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.pairingCelebrationPairedHeaderLabel(partnerName)))
        .task(id: currentProfilePhotoAssetID) {
            await currentPhoto.load(assetID: currentProfilePhotoAssetID, provider: profilePhotoProvider)
        }
        .task(id: partnerProfilePhotoAssetID) {
            await partnerPhoto.load(assetID: partnerProfilePhotoAssetID, provider: profilePhotoProvider)
        }
    }
}

#if DEBUG
#Preview {
    PairedProfilesHeader(
        currentName: "Hjalmar",
        partnerName: "Oda"
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
