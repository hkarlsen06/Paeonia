import SwiftUI

/// The settled "two people linked by a heart" element, reused at the top of the
/// paired Home tab: each person's avatar, their names, and the beating-heart
/// connector between them. This is the same arrangement that lands at the end of
/// the pairing celebration.
///
/// Profile photos load the same way the celebration loads them, falling back to
/// initials while they load or when none is set.
struct PairedProfilesHeader: View {
    private static let coordinateSpace = "pairedProfilesHeader"

    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    private let profilePhotoProvider: (any ProfilePhotoImageProviding)?

    @State private var currentPhotoData: Data?
    @State private var partnerPhotoData: Data?

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

    private var photoLoadID: String {
        [
            currentProfilePhotoAssetID?.uuidString ?? "none",
            partnerProfilePhotoAssetID?.uuidString ?? "none"
        ].joined(separator: "|")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PairingCelebrationProfilesView(
            currentName: currentName,
            currentPhotoData: currentPhotoData,
            partnerName: partnerName,
            partnerPhotoData: partnerPhotoData,
            partnerSlotIsPlaceholder: false,
            surroundingsOpacity: 1,
            slotCoordinateSpace: Self.coordinateSpace,
            metrics: .compact,
            onPartnerSlotChange: { _ in }
        )
        // Crossfade between initials and photo, and between different photos on
        // reload. Keyed on the pair of asset IDs so the animation triggers only
        // when the actual identity changes, not on every render.
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: currentPhotoData)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: partnerPhotoData)
        .task(id: photoLoadID) {
            await loadProfilePhotos()
        }
    }

    @MainActor
    private func loadProfilePhotos() async {
        guard let profilePhotoProvider else {
            return
        }

        // Do NOT clear the photos to nil before the new load completes.
        // Clearing eagerly causes the avatar to flash back to initials on every
        // reload (e.g. when photoLoadID changes because names refreshed). Instead
        // we keep the last-known photo visible until the new value arrives, then
        // replace it in one step. If the asset ID genuinely became nil the load
        // returns nil and the initials appear once — after the crossfade — not
        // before.

        async let current = profilePhotoProvider.profilePhotoData(for: currentProfilePhotoAssetID)
        async let partner = profilePhotoProvider.profilePhotoData(for: partnerProfilePhotoAssetID)
        let (currentData, partnerData) = await (current, partner)

        guard !Task.isCancelled else {
            return
        }

        currentPhotoData = currentData
        partnerPhotoData = partnerData
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
