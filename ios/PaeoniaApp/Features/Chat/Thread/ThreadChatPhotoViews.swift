import SwiftUI
import UIKit

/// Sizes and cache keys for chat photos, ported from Tidex's chat.
enum ThreadChatPhotoLayout {
    /// The longest side of the decoded copy kept for the chat. Big enough for the
    /// largest bubble on a 3x screen.
    static let displayPixelSize = 660

    /// A fixed frame from the photo's stored size, so its row never changes height
    /// when the image arrives. Wide photos fill the width, tall ones the height,
    /// neither shorter than `minDimension`.
    static func frameSize(
        for photo: ThreadChatPhoto,
        maxDimension: CGFloat = 220,
        minDimension: CGFloat = 120
    ) -> CGSize {
        guard let width = photo.width, let height = photo.height, width > 0, height > 0 else {
            return CGSize(width: 180, height: 180)
        }
        let aspectRatio = CGFloat(width) / CGFloat(height)
        if aspectRatio >= 1 {
            let scaledHeight = max(minDimension, maxDimension / aspectRatio)
            return CGSize(width: maxDimension, height: min(maxDimension, scaledHeight))
        }
        let scaledWidth = max(minDimension, maxDimension * aspectRatio)
        return CGSize(width: min(maxDimension, scaledWidth), height: maxDimension)
    }

    /// The memory cache key for a photo's chat copy. A photo still sending has no
    /// asset id yet, so its bytes name it.
    static func cacheKey(for photo: ThreadChatPhoto) -> String? {
        if let mediaAssetID = photo.mediaAssetID { return "chat-\(mediaAssetID.uuidString)" }
        guard let data = photo.data else { return nil }
        return "chat-local-\(data.count)-\(data.prefix(48).base64EncodedString())"
    }

    /// Decodes a photo's bytes to the chat copy and keeps it in memory under `key`.
    static func decodeAndCache(_ data: Data, key: String) async -> UIImage? {
        guard let image = await MemoryImageDecoding.downsample(data, maxPixelSize: displayPixelSize) else {
            return nil
        }
        PaeoniaImageMemoryCache.store(image, forKey: key)
        return image
    }
}

/// One photo in a chat message, at a fixed size. It shows straight away from memory
/// when it was shown before, plays from this phone's copy while sending, and loads
/// the uploaded file otherwise.
struct ThreadChatPhotoCard: View {
    let photo: ThreadChatPhoto
    let size: CGSize
    let shape: UnevenRoundedRectangle
    var isCurrentUser = false
    var provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared

    @State private var image: UIImage?
    @State private var didFail = false

    init(
        photo: ThreadChatPhoto,
        size: CGSize,
        shape: UnevenRoundedRectangle,
        isCurrentUser: Bool = false,
        provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared
    ) {
        self.photo = photo
        self.size = size
        self.shape = shape
        self.isCurrentUser = isCurrentUser
        self.provider = provider
        // A photo shown before is in the first frame, with no placeholder in between.
        let cached = ThreadChatPhotoLayout.cacheKey(for: photo).flatMap(PaeoniaImageMemoryCache.image(forKey:))
        _image = State(initialValue: cached)
    }

    var body: some View {
        shape
            .fill(.paeoniaSurfacePrimary)
            .frame(width: size.width, height: size.height)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .accessibilityHidden(true)
                } else if didFail {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isCurrentUser ? Color.white.opacity(0.2) : Color.paeoniaSurfacePressed.opacity(0.45),
                    lineWidth: 1
                )
            }
            .task(id: ThreadChatPhotoLayout.cacheKey(for: photo)) { await load() }
            .accessibilityElement()
            .accessibilityLabel(Text(.dailyChatPhotoPreview))
            .accessibilityAddTraits(.isImage)
    }

    private func load() async {
        guard image == nil, let key = ThreadChatPhotoLayout.cacheKey(for: photo) else { return }
        if let cached = PaeoniaImageMemoryCache.image(forKey: key) {
            image = cached
            return
        }
        let data: Data? = if let local = photo.data {
            local
        } else if let mediaAssetID = photo.mediaAssetID {
            await provider?.imageData(for: mediaAssetID)
        } else {
            nil
        }
        guard !Task.isCancelled else { return }
        if let data, let decoded = await ThreadChatPhotoLayout.decodeAndCache(data, key: key) {
            image = decoded
        } else {
            didFail = true
        }
    }
}

/// Up to three small thumbnails of a quoted message's photos, the last one marked
/// "+N" when there are more. Like Tidex's reply preview.
struct ThreadChatPhotoThumbnails: View {
    let photos: [ThreadChatPhoto]
    var singleSize: CGFloat = 56

    var body: some View {
        let shown = photos.prefix(3)
        let side = photos.count > 1 ? min(singleSize, 34) : singleSize
        let overflow = photos.count - shown.count
        HStack(spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, photo in
                ThreadChatPhotoCard(
                    photo: photo,
                    size: CGSize(width: side, height: side),
                    shape: UnevenRoundedRectangle(cornerRadii: .init(
                        topLeading: 8, bottomLeading: 8, bottomTrailing: 8, topTrailing: 8
                    ), style: .continuous)
                )
                .overlay {
                    if overflow > 0, index == shown.count - 1 {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .overlay {
                                Text(verbatim: "+\(overflow)")
                                    .font(PaeoniaTypography.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
