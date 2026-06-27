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

            PhotosPicker(selection: $selection, matching: .images) {
                Label {
                    Text(.dailyChallengePhotoChange)
                } icon: {
                    Image(systemName: "photo.on.rectangle").accessibilityHidden(true)
                }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
        }
    }

    private var photoPlaceholderPicker: some View {
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
