import SwiftUI

/// The two people at the top of the restore screens: this person's photo and the
/// former partner's, leaning in toward each other with a heart where they meet.
/// While the person waits for the answer, the heart beats softly.
struct RelationshipRestoreCouple: View {
    let ownName: String
    let ownPhotoAssetID: UUID?
    let partnerName: String
    let partnerPhotoAssetID: UUID?
    /// Loads the partner's photo on the join screen, where it comes from a signed
    /// link instead of an asset. Nil uses the app's photo provider.
    var partnerPhotoProvider: (any ProfilePhotoImageProviding)?
    var isWaiting = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Photos don't need to grow with the text, so at the largest text sizes they
    /// shrink to leave the words more room.
    private var avatarSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 84 : 104 }
    private var ringWidth: CGFloat { 4 }
    private var heartSize: CGFloat { avatarSize * 0.44 }

    var body: some View {
        HStack(spacing: -avatarSize * 0.16) {
            avatar(name: ownName, photo: ownPhotoAssetID, tint: .paeoniaPartnerOne, provider: nil)
                .rotationEffect(.degrees(-6))
            avatar(
                name: partnerName, photo: partnerPhotoAssetID, tint: .paeoniaPartnerTwo, provider: partnerPhotoProvider
            )
                .rotationEffect(.degrees(6))
        }
        .overlay(alignment: .bottom) {
            heart
                .offset(y: heartSize * 0.3)
        }
        .padding(.bottom, heartSize * 0.3)
        // The title under it names both people.
        .accessibilityHidden(true)
    }

    private func avatar(
        name: String, photo: UUID?, tint: Color, provider: (any ProfilePhotoImageProviding)?
    ) -> some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: photo,
            name: name,
            tint: tint,
            size: avatarSize,
            profilePhotoProvider: provider
        )
        .padding(ringWidth)
        .background(.paeoniaBackgroundPrimary, in: Circle())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    @ViewBuilder
    private var heart: some View {
        let image = Image(.homeHeart)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .frame(width: heartSize, height: heartSize)
            .shadow(color: .paeoniaAccentPrimary.opacity(0.45), radius: 10, y: 4)
        if isWaiting, !reduceMotion {
            image.phaseAnimator([1, 1.12]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                PaeoniaMotion.standardCurve(duration: 0.8)
            }
        } else {
            image
        }
    }
}
