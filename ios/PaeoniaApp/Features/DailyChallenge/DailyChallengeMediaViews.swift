import PhotosUI
import SwiftUI
import UIKit

/// Shared provider for revealed answer images, created once. Nil when the Supabase
/// client can't be configured (previews/tests), in which case images show a quiet
/// placeholder instead of loading.
nonisolated enum DailyAnswerMediaImageProviderFactory {
    static let shared: (any DailyAnswerMediaImageProviding)? = try? DailyAnswerMediaImageService.live()
}

/// A small pill row for choosing which kind to answer with, shown only when a
/// question genuinely accepts more than one (e.g. photo or text).
struct DailyAnswerKindPicker: View {
    let kinds: [DailyChallengeAnswerKind]
    let selection: DailyChallengeAnswerKind?
    let onSelect: (DailyChallengeAnswerKind) -> Void

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
            .foregroundStyle(isSelected ? Color.paeoniaTextInverse : Color.paeoniaTextSecondary)
            .background(isSelected ? Color.paeoniaAccentPrimary : Color.paeoniaSurfaceSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.stateChange, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Picks and previews a single photo answer from the library. The Send action lives
/// in the flow's bottom bar, like the other composers.
struct DailyPhotoAnswerComposer: View {
    let imageData: Data?
    let onPick: (Data) -> Void
    let onRemove: () -> Void

    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var isCameraPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.dailyChallengePhotoLabel)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)

            if let imageData, let uiImage = UIImage(data: imageData) {
                pickedPhoto(uiImage)
            } else {
                photoPlaceholderPicker
            }
        }
        .onChange(of: selection) { _, item in
            loadSelection(item)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            DailyCameraPicker(onCapture: onPick)
                .ignoresSafeArea()
        }
    }

    private func pickedPhoto(_ uiImage: UIImage) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
                .padding(PaeoniaSpacing.space8)
                .accessibilityLabel(Text(.dailyChallengePhotoRemove))
            }

            HStack(spacing: PaeoniaSpacing.space8) {
                PhotosPicker(selection: $selection, matching: .images) {
                    Label {
                        Text(.dailyChallengePhotoChange)
                    } icon: {
                        Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
                    }
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .frame(maxWidth: .infinity)

                cameraButton
            }
        }
    }

    @ViewBuilder
    private var cameraButton: some View {
        if DailyCameraPicker.isAvailable {
            Button {
                isCameraPresented = true
            } label: {
                Label {
                    Text(.dailyChallengePhotoTake)
                } icon: {
                    Image(systemName: "camera").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
        }
    }

    private var photoPlaceholderPicker: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(selection: $selection, matching: .images) {
                VStack(spacing: PaeoniaSpacing.space8) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .accessibilityHidden(true)
                        Text(.dailyChallengePhotoAdd)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(.paeoniaBackgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                        .stroke(Color.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                }
            }
            .buttonStyle(.plain)

            cameraButton
        }
    }

    private func loadSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoading = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                onPick(data)
            }
            isLoading = false
            selection = nil
        }
    }
}

/// Shown for a media answer that's saved on the device and finishing its upload in
/// the background, so the user knows it's handled even when they're offline. A photo
/// shows a thumbnail; a voice note stays playable straight from its staged bytes.
struct DailySendingAnswerView: View {
    let mediaKind: DailyChallengeAnswerKind
    let mediaData: Data?
    var voiceDurationMs: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            preview
            DailySendingStatusLine()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if mediaKind == .voice {
            if let mediaData {
                DailyVoicePlaybackView(source: .data(mediaData), fallbackDurationMs: voiceDurationMs)
            }
        } else if let mediaData, let uiImage = UIImage(data: mediaData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        }
    }
}

/// Shown for a text or partner-choice answer that's saved on the device and finishing
/// its send in the background, so the user sees what they wrote is safe — even offline
/// — instead of an error asking them to try again.
struct DailySendingSimpleAnswerView: View {
    let content: DailySendingSimpleContent

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            preview
            DailySendingStatusLine()
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch content {
        case let .text(body):
            Text(body)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        case let .partnerChoice(name):
            Text(name)
                .font(PaeoniaTypography.body.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
/// it, and shows a quiet placeholder while loading or if it can't be fetched.
struct DailyAnswerImageView: View {
    let mediaAssetID: UUID?
    var provider: (any DailyAnswerMediaImageProviding)? = DailyAnswerMediaImageProviderFactory.shared
    var height: CGFloat = 220

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .task(id: mediaAssetID) { await load() }
            .accessibilityLabel(Text(.dailyChallengePhotoAnswerAccessibility))
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if didFail {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
        }
    }

    private func load() async {
        image = nil
        didFail = false

        guard let mediaAssetID, let provider else {
            didFail = true
            return
        }

        let data = await provider.imageData(for: mediaAssetID)
        if let data, let loaded = UIImage(data: data) {
            image = loaded
        } else {
            didFail = true
        }
    }
}
