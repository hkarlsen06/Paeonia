import SwiftUI
import UIKit

/// Sizes, cache keys and files for chat attachments, ported from Tidex's chat.
enum ThreadChatAttachmentLayout {
    /// The longest side of the decoded copy kept for the chat. Big enough for the
    /// largest bubble on a 3x screen.
    static let displayPixelSize = 660

    /// A fixed frame from the attachment's stored size, so its row never changes height
    /// when the image arrives. Wide ones fill the width, tall ones the height,
    /// neither shorter than `minDimension`.
    static func frameSize(
        for attachment: ThreadChatAttachment,
        maxDimension: CGFloat = 220,
        minDimension: CGFloat = 120
    ) -> CGSize {
        guard let width = attachment.width, let height = attachment.height, width > 0, height > 0 else {
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

    /// The memory cache key for an attachment's chat picture, a video's first frame
    /// included. One still sending has no asset id yet, so its bytes or its file name it.
    static func cacheKey(for attachment: ThreadChatAttachment) -> String? {
        let prefix = attachment.kind == .video ? "chat-video-" : "chat-"
        if let mediaAssetID = attachment.mediaAssetID { return prefix + mediaAssetID.uuidString }
        return switch attachment.local {
        case let .bytes(data): "chat-local-\(data.count)-\(data.prefix(48).base64EncodedString())"
        case let .file(name): prefix + "local-\(name)"
        case nil: nil
        }
    }

    /// Keeps a sent video's first frame under its uploaded asset's key, so the bubble that
    /// replaces the one still sending shows it without a spinner.
    static func cacheSentPoster(
        ofVideoNamed name: String,
        for mediaAssetID: UUID,
        generation: PurgeableImageCache.Generation
    ) async {
        guard let sentKey = cacheKey(for: ThreadChatAttachment(kind: .video, mediaAssetID: mediaAssetID)) else {
            return
        }
        let localKey = cacheKey(for: ThreadChatAttachment(kind: .video, local: .file(name: name)))
        var poster = localKey.flatMap(PaeoniaImageMemoryCache.image(forKey:))
        if poster == nil {
            poster = await VideoPoster.image(
                for: ThreadChatMediaFiles.url(named: name), maxPixelSize: CGFloat(displayPixelSize)
            )
        }
        if let poster { PaeoniaImageMemoryCache.store(poster, forKey: sentKey, generation: generation) }
    }

    /// Decodes a photo's bytes to the chat copy and keeps it in memory under `key`, unless
    /// a privacy purge ran since `generation` was read.
    static func decodeAndCache(
        _ data: Data,
        key: String,
        generation: PurgeableImageCache.Generation
    ) async -> UIImage? {
        guard let image = await MemoryImageDecoding.downsample(data, maxPixelSize: displayPixelSize) else {
            return nil
        }
        PaeoniaImageMemoryCache.store(image, forKey: key, generation: generation)
        return image
    }

    /// A photo's or a GIF's bytes, from this phone's copy or the downloaded file.
    nonisolated static func imageData(
        of attachment: ThreadChatAttachment,
        provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared
    ) async -> Data? {
        if let local = attachment.localBytes { return local }
        if let file = attachment.localFileURL, let local = try? Data(contentsOf: file, options: .mappedIfSafe) {
            return local
        }
        guard let mediaAssetID = attachment.mediaAssetID else { return nil }
        return await provider?.imageData(for: mediaAssetID)
    }

    /// A video's file: the sender's prepared copy while it is still on this phone,
    /// otherwise the video cache's, which downloads it the first time.
    nonisolated static func videoFile(
        of attachment: ThreadChatAttachment, priority: VideoFileCache.Priority = .poster
    ) async throws -> URL {
        if let local = attachment.localFileURL, FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        guard let mediaAssetID = attachment.mediaAssetID, let cache = VideoFileCache.shared else {
            throw VideoFileCacheError.unavailable
        }
        return try await cache.fileURL(for: mediaAssetID, priority: priority)
    }
}

/// One photo, GIF or video in a chat message, at a fixed size. A photo shows straight
/// away from memory when it was shown before, a GIF moves, and a video shows its first
/// frame with its length. Each plays from this phone's copy while sending, and loads the
/// uploaded file otherwise. A video never plays here. Tapping it opens the player.
struct ThreadChatAttachmentCard: View {
    let attachment: ThreadChatAttachment
    let size: CGSize
    let shape: UnevenRoundedRectangle
    var isCurrentUser = false
    /// Small thumbnails mark a video with a play glyph instead of its length.
    var showsVideoLength = true
    var provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared

    private struct LoadedGIF {
        let key: String
        let data: Data
    }

    @State private var load = ImageLoad<String>.loading
    @State private var gif: LoadedGIF?

    init(
        attachment: ThreadChatAttachment,
        size: CGSize,
        shape: UnevenRoundedRectangle,
        isCurrentUser: Bool = false,
        showsVideoLength: Bool = true,
        provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared
    ) {
        self.attachment = attachment
        self.size = size
        self.shape = shape
        self.isCurrentUser = isCurrentUser
        self.showsVideoLength = showsVideoLength
        self.provider = provider
        // A picture shown before is in the first frame, with no placeholder in between.
        if let key = ThreadChatAttachmentLayout.cacheKey(for: attachment),
           let cached = PaeoniaImageMemoryCache.image(forKey: key) {
            _load = State(initialValue: .loaded(key, cached))
        }
    }

    var body: some View {
        shape
            .fill(.paeoniaSurfacePrimary)
            .frame(width: size.width, height: size.height)
            .overlay { picture }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isCurrentUser ? Color.white.opacity(0.2) : Color.paeoniaBorder.opacity(0.45),
                    lineWidth: 1
                )
            }
            .overlay(alignment: showsVideoLength ? .bottomLeading : .center) { videoMark }
            .task(id: ThreadChatAttachmentLayout.cacheKey(for: attachment)) { await loadPicture() }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var picture: some View {
        let key = ThreadChatAttachmentLayout.cacheKey(for: attachment)
        if let key, let gif, gif.key == key {
            AnimatedImageView(id: gif.key, data: gif.data)
                .frame(width: size.width, height: size.height)
        } else if let key, let image = load.image(for: key) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
        } else if let key, load.hasFailed(for: key) {
            Image(systemName: attachment.kind == .video ? "video" : "photo")
                .font(.title3)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var videoMark: some View {
        if attachment.kind == .video {
            if showsVideoLength {
                VideoBadge(durationMs: attachment.durationMs)
                    .padding(PaeoniaSpacing.space8)
            } else {
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var accessibilityLabel: String {
        let description = attachment.accessibilityText?.trimmedNonEmpty
        switch attachment.kind {
        case .photo, .gif:
            return description ?? String(localized: attachment.previewLabel)
        case .video:
            return VideoBadge.accessibilityLabel(durationMs: attachment.durationMs, description: description)
        }
    }

    private func loadPicture() async {
        guard let key = ThreadChatAttachmentLayout.cacheKey(for: attachment) else { return }
        if attachment.kind == .gif {
            await loadGIF(key: key)
            return
        }
        if let cached = PaeoniaImageMemoryCache.image(forKey: key) {
            load = .loaded(key, cached)
            return
        }
        load = .loading
        let generation = PaeoniaImageMemoryCache.generation
        let decoded: UIImage? = switch attachment.kind {
        case .video: await poster(key: key, generation: generation)
        case .photo, .gif: await photo(key: key, generation: generation)
        }
        guard !Task.isCancelled else { return }
        // Only a picture that had to load fades in over the spinner. A cached one is
        // set above without animation, so scrolling and cell reuse never fade.
        withAnimation(PaeoniaMotion.stateChange) {
            load = ImageLoad(decoded, for: key)
        }
    }

    private func photo(key: String, generation: PurgeableImageCache.Generation) async -> UIImage? {
        guard let data = await ThreadChatAttachmentLayout.imageData(of: attachment, provider: provider),
              !Task.isCancelled
        else { return nil }
        return await ThreadChatAttachmentLayout.decodeAndCache(data, key: key, generation: generation)
    }

    private func poster(key: String, generation: PurgeableImageCache.Generation) async -> UIImage? {
        guard let file = try? await ThreadChatAttachmentLayout.videoFile(of: attachment), !Task.isCancelled,
              let poster = await VideoPoster.image(
                for: file, maxPixelSize: CGFloat(ThreadChatAttachmentLayout.displayPixelSize)
              )
        else { return nil }
        PaeoniaImageMemoryCache.store(poster, forKey: key, generation: generation)
        return poster
    }

    private func loadGIF(key: String) async {
        guard gif?.key != key else { return }
        let data = await ThreadChatAttachmentLayout.imageData(of: attachment, provider: provider)
        guard !Task.isCancelled else { return }
        if let data {
            gif = LoadedGIF(key: key, data: data)
        } else {
            load = .failed(key)
        }
    }
}

/// Up to three small thumbnails of a quoted message's attachments, the last one marked
/// "+N" when there are more. Like Tidex's reply preview.
struct ThreadChatAttachmentThumbnails: View {
    let attachments: [ThreadChatAttachment]
    var singleSize: CGFloat = 56

    var body: some View {
        let shown = attachments.prefix(3)
        let side = attachments.count > 1 ? min(singleSize, 34) : singleSize
        let overflow = attachments.count - shown.count
        HStack(spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, attachment in
                ThreadChatAttachmentCard(
                    attachment: attachment,
                    size: CGSize(width: side, height: side),
                    shape: UnevenRoundedRectangle(cornerRadii: .init(
                        topLeading: 8, bottomLeading: 8, bottomTrailing: 8, topTrailing: 8
                    ), style: .continuous),
                    showsVideoLength: false
                )
                .id(ThreadChatAttachmentLayout.cacheKey(for: attachment))
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
