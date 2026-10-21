import SwiftUI
import UIKit

/// What the share sheet offers for a story: the photo, with its caption on it as
/// the viewer shows it.
///
/// A story is a small check-in that one partner makes for the other, so only its
/// author can send it on. The partner can save it to their own Photos, like a
/// photo in the chat, but the share sheet is not offered, because that would pass
/// the author's photo to other people in one tap.
enum StoryShare {
    static func shareable(for story: Story, people: StoryPeople) -> PaeoniaShareable {
        let mediaAssetID = story.mediaAssetID
        let caption = story.caption
        return PaeoniaShareable(
            title: String(localized: .shareTitleStory),
            allowsSharing: people.isOwn(story)
        ) {
            guard let data = await MemoryMediaImageProviderFactory.shared?.imageData(for: mediaAssetID),
                  let photo = UIImage(data: data)
            else { return nil }
            return image(of: photo, caption: caption)
        }
    }

    /// The photo as a JPEG, upright, with the caption over its lower edge when the
    /// story has one.
    static func image(of photo: UIImage, caption: String?) -> PaeoniaShareImage? {
        guard let caption, !caption.isEmpty else {
            return photo.jpegData(compressionQuality: 0.92).map { PaeoniaShareImage(data: $0, format: .jpeg) }
        }
        let pixelSize = CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        return PaeoniaShareRenderer.jpeg(
            StoryShareCaptionedPhoto(photo: photo, caption: caption, width: pixelSize.width),
            pixelSize: pixelSize
        )
    }
}

/// The photo with the caption in the dark pill the viewer uses. Sizes follow the
/// photo's width, so the caption looks the same on a small photo and a large one.
private struct StoryShareCaptionedPhoto: View {
    let photo: UIImage
    let caption: String
    let width: CGFloat

    var body: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .accessibilityHidden(true)
            .overlay(alignment: .bottom) {
                Text(verbatim: caption)
                    .font(.system(size: width * 0.045, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, width * 0.04)
                    .padding(.vertical, width * 0.03)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: width * 0.04))
                    .padding(.horizontal, width * 0.06)
                    .padding(.bottom, width * 0.08)
            }
            .clipped()
    }
}
