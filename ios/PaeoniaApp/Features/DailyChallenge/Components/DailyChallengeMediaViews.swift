import SwiftUI
import UIKit

/// Shared provider for revealed answer images, created once. Nil when the Convex
/// client can't be configured (previews/tests), in which case images show a quiet
/// placeholder instead of loading.
nonisolated enum DailyAnswerMediaImageProviderFactory {
    static let shared: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageService.shared
}

/// A small pill row for choosing which kind to answer with, shown only when a
/// question genuinely accepts more than one (e.g. photo or text).
struct DailyAnswerKindPicker: View {
    let kinds: [DailyChallengeAnswerKind]
    let selection: DailyChallengeAnswerKind?
    let onSelect: (DailyChallengeAnswerKind) -> Void

    @Environment(\.dailyAnswerComposerColors) private var colors

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            ForEach(kinds) { kind in
                pill(for: kind)
            }
        }
    }

    private func pill(for kind: DailyChallengeAnswerKind) -> some View {
        let isSelected = kind == selection
        return Button {
            PaeoniaHaptics.selection()
            onSelect(kind)
        } label: {
            Label {
                Text(kind.composerTitle)
            } icon: {
                Image(systemName: kind.composerIcon).accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .foregroundStyle(isSelected ? colors.foreground : colors.secondary)
            // Unselected pills are darker than the question card they sit on.
            .background(isSelected ? colors.selected : colors.control)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.stateChange, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Shown for a media answer that's saved on the device and finishing its upload in
/// the background, so the user knows it's handled even when they're offline. A photo
/// shows a thumbnail; a voice note stays playable straight from its staged bytes.
/// Shows whatever a still-sending answer carries — a photo or voice note, a partner
/// pick, and/or a text caption — so the user sees what they saved is safe (even
/// offline) while it finishes sending. A combined answer shows all of its parts.
struct DailySendingAnswerView: View {
    var mediaKind: DailyChallengeAnswerKind = .photo
    var mediaData: Data?
    var voiceDurationMs: Int?
    var partnerChoiceName: String?
    var text: String?
    /// Whether to show the "saved on this phone, sending" line under the answer. Pass
    /// true only once a try to send it failed, so a normal send never flashes the line.
    /// The partner-answer reveal flow passes false so the just-sent answer reads as
    /// the settled answered state while it holds for the reveal.
    let showsSendingStatus: Bool

    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            mediaPreview

            if let partnerChoiceName {
                Text(partnerChoiceName)
                    .font(PaeoniaTypography.body.weight(.semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
            }

            if let text, !text.isEmpty {
                Text(text)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsSendingStatus {
                DailySendingStatusLine()
            }
        }
        .paeoniaImageViewer(selection: $imageViewerSelection)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if mediaKind == .voice {
            if let mediaData {
                DailyVoicePlaybackView(source: .data(mediaData), fallbackDurationMs: voiceDurationMs)
            }
        } else if let mediaData {
            DailyDecodedPhoto(data: mediaData, reservedHeight: 220) { uiImage in
                // Sized by the rectangle, with the photo as a clipped overlay — so a
                // `scaledToFill` photo crops within these bounds rather than widening the
                // card (same reason as `DailyAnswerImageView`).
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                    .fill(.paeoniaSurfaceSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .overlay {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
                    .onTapGesture {
                        imageViewerSelection = PaeoniaImageViewerSelection(image: uiImage)
                    }
                    .accessibilityLabel(Text(.dailyChallengePhotoAnswerAccessibility))
                    .accessibilityAddTraits(.isButton)
            } failure: {
                EmptyView()
            }
        }
    }
}

/// The shared "saved on this phone, sending" line under every still-sending answer.
private struct DailySendingStatusLine: View {
    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)

            Text(.dailyChallengeSendingMessage)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Loads and shows a revealed photo answer. Fetches a signed download once, caches
/// it, and shows a quiet placeholder while loading. If the download fails, tapping
/// the placeholder tries again.
struct DailyAnswerImageView: View {
    let mediaAssetID: UUID?
    var provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared
    var height: CGFloat = 220
    var allowsViewing = true

    @State private var image: UIImage?
    @State private var didFail = false
    /// Bumped by a tap on the failed placeholder to run the load again.
    @State private var attempt = 0
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    init(
        mediaAssetID: UUID?,
        provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared,
        height: CGFloat = 220,
        allowsViewing: Bool = true
    ) {
        self.mediaAssetID = mediaAssetID
        self.provider = provider
        self.height = height
        self.allowsViewing = allowsViewing
        // A photo shown before is in the first frame, with no placeholder in between.
        let cached = Self.cacheKey(for: mediaAssetID, height: height).flatMap(PaeoniaImageMemoryCache.image(forKey:))
        _image = State(initialValue: cached)
    }

    /// The memory cache holds the copy decoded for this frame height, not the full photo.
    private static func cacheKey(for mediaAssetID: UUID?, height: CGFloat) -> String? {
        mediaAssetID.map { "answer-\($0.uuidString)-\(MemoryImageDecoding.maxPixelSize(forHeight: height))" }
    }

    private struct LoadKey: Hashable {
        let mediaAssetID: UUID?
        let attempt: Int
    }

    var body: some View {
        // The surface rectangle owns the size (full available width × fixed height), so
        // the photo rides as a clipped overlay. A `scaledToFill` image used as the base
        // view reports its oversized fill dimensions to layout and widens the whole
        // card; as an overlay it fills and crops within these bounds instead.
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            .fill(.paeoniaSurfaceSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            // The revealed photo (or the failure glyph) fades in over the quiet
            // placeholder instead of snapping into the frame when the download lands.
            .animation(PaeoniaMotion.stateChange, value: image != nil)
            .animation(PaeoniaMotion.stateChange, value: didFail)
            .task(id: LoadKey(mediaAssetID: mediaAssetID, attempt: attempt)) { await load() }
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .onTapGesture {
                if didFail {
                    attempt += 1
                } else {
                    presentImageViewer()
                }
            }
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits((image != nil && allowsViewing) || didFail ? .isButton : [])
            .paeoniaImageViewer(selection: $imageViewerSelection)
    }

    private var accessibilityLabel: LocalizedStringResource {
        didFail ? .dailyChallengePhotoLoadFailed : .dailyChallengePhotoAnswerAccessibility
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if didFail {
            VStack(spacing: PaeoniaSpacing.space8) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                    .foregroundStyle(.paeoniaTextTertiary)
                Text(.dailyChallengePhotoLoadFailed)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(PaeoniaSpacing.space12)
            .accessibilityHidden(true)
        } else {
            ProgressView()
        }
    }

    private func load() async {
        // Already showing this photo from memory. A new photo or a retry loads again.
        let key = Self.cacheKey(for: mediaAssetID, height: height)
        if let image, let key, image === PaeoniaImageMemoryCache.image(forKey: key) { return }
        image = nil
        didFail = false

        guard let mediaAssetID, let provider, let key else {
            didFail = true
            return
        }

        let data = await provider.imageData(for: mediaAssetID)
        guard !Task.isCancelled else { return }
        // Decoded off the main thread at the size this frame needs, so the memory cache
        // pays for that copy and not for the full camera photo.
        let loaded: UIImage? = if let data {
            await MemoryImageDecoding.downsample(
                data,
                maxPixelSize: MemoryImageDecoding.maxPixelSize(forHeight: height)
            )
        } else {
            nil
        }
        guard !Task.isCancelled else { return }
        if let loaded {
            image = loaded
            PaeoniaImageMemoryCache.store(loaded, forKey: key)
        } else {
            didFail = true
        }
    }

    /// The viewer zooms, so it gets a larger copy than the frame shows.
    private func presentImageViewer() {
        guard allowsViewing, let image else { return }
        guard let mediaAssetID, let provider else {
            imageViewerSelection = PaeoniaImageViewerSelection(image: image)
            return
        }
        Task {
            let data = await provider.imageData(for: mediaAssetID)
            let large: UIImage? = if let data {
                await MemoryImageDecoding.downsample(data, maxPixelSize: Self.viewerPixelSize)
            } else {
                nil
            }
            imageViewerSelection = PaeoniaImageViewerSelection(id: mediaAssetID, image: large ?? image)
        }
    }

    private static let viewerPixelSize = 2_048
}
