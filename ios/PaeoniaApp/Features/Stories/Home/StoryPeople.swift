import SwiftUI

/// The two partners as the story screens show them.
struct StoryPeople: Equatable {
    var currentUserID: UUID?
    var currentName: String
    var currentPhotoAssetID: UUID?
    var partnerUserID: UUID?
    var partnerName: String
    var partnerPhotoAssetID: UUID?

    func isOwn(_ story: Story) -> Bool {
        story.authorUserID == currentUserID
    }

    func name(of story: Story) -> String {
        isOwn(story) ? currentName : partnerName
    }

    func photoAssetID(of story: Story) -> UUID? {
        isOwn(story) ? currentPhotoAssetID : partnerPhotoAssetID
    }

    func tint(of story: Story) -> Color {
        isOwn(story) ? .paeoniaPartnerOne : .paeoniaPartnerTwo
    }
}

/// A profile photo with the story ring around it.
struct StoryRingAvatar: View {
    let mediaAssetID: UUID?
    let name: String
    let tint: Color
    let ring: StoryRingState
    var size: CGFloat = 60

    /// The space between the photo and the ring.
    static let ringGap = PaeoniaSpacing.space4

    var body: some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: mediaAssetID, name: name, tint: tint, size: size)
            .padding(Self.ringGap)
            .overlay { ringShape }
            .animation(PaeoniaMotion.stateChange, value: ring)
    }

    @ViewBuilder
    private var ringShape: some View {
        switch ring {
        case .unseen:
            Circle().strokeBorder(
                AngularGradient(
                    colors: [.paeoniaAccentPrimary, .paeoniaPartnerTwo, .paeoniaInkGold, .paeoniaAccentPrimary],
                    center: .center
                ),
                lineWidth: 3
            )
        case .seen:
            Circle().strokeBorder(.paeoniaTextTertiary, lineWidth: PaeoniaRadius.strokeDefault)
        case .noStory:
            EmptyView()
        }
    }
}
