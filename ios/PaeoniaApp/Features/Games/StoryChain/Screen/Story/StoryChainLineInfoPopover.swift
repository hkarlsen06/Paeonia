import SwiftUI

/// What the popover shows when someone taps a line: who wrote it and when, and
/// the dared word when the line used one. The page owns the popover and this
/// view fills it.
struct StoryChainLineInfoPopover: View {
    /// "You" for my own lines.
    let name: String
    let isMine: Bool
    let mediaAssetID: UUID?
    let createdAt: Date
    let usedDare: String?

    var body: some View {
        StoryChainLineInfoView(
            name: name,
            time: createdAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
            usedDare: usedDare.map { Text(.storyChainPageUsedWord($0.uppercased())) }
        ) {
            StoryChainAvatar(mediaAssetID: mediaAssetID, name: name, isMe: isMine, size: 32)
                .accessibilityHidden(true)
        }
    }
}
