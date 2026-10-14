import SwiftUI

/// The star toggle in the trailing toolbar of a finished story. Stars are
/// private, so the first one a person sets also says so in a quiet banner when
/// `showsPrivacyHint` is on. The history detail shows the same fact as a caption
/// instead.
struct StoryChainStarButton: View {
    let stars: StoryChainStars
    let storyID: UUID
    var showsPrivacyHint = false
    var identifier = "storyChain.star"

    @AppStorage("games.storyChain.starHintShown") private var hintShown = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        let isStarred = stars.isStarred(storyID)
        let title: LocalizedStringResource = isStarred ? .storyChainStarred : .storyChainStar
        Button {
            PaeoniaHaptics.selection()
            Task { await stars.toggle(storyID: storyID) }
            if showsPrivacyHint, !isStarred, !hintShown {
                hintShown = true
                bannerCenter.show(
                    .info(message: String(localized: .storyChainStarPrivacy), systemImage: "star.fill")
                )
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: isStarred ? "star.fill" : "star")
            }
        }
        .accessibilityAddTraits(isStarred ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
