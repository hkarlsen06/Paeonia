import PhotosUI
import SwiftUI
import UIKit

/// One picked photo, kept as a thumbnail while the caption is being written.
struct DailyPhotoAnswerComposer: View {
    let imageData: Data?
    var isPreparing = false
    var isCompact = false
    var previewHeight: CGFloat = 170
    let onPick: (Data) -> Void
    var onPickFailed: () -> Void = {}
    let onRemove: () -> Void

    @Environment(\.dailyAnswerComposerColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var isCameraPresented = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    private var isBusy: Bool { isLoading || isPreparing }

    var body: some View {
        Group {
            if let imageData {
                DailyDecodedPhoto(data: imageData, reservedHeight: isCompact ? 44 : previewHeight) { image in
                    // With Reduce Motion the two sizes crossfade instead of resizing.
                    stagedPhoto(image).id(reduceMotion && isCompact)
                } failure: {
                    picker
                }
            } else {
                picker
            }
        }
        .onChange(of: selection) { _, item in loadSelection(item) }
        .fullScreenCover(isPresented: $isCameraPresented) {
            DailyCameraPicker(onCapture: onPick).ignoresSafeArea()
        }
        .paeoniaImageViewer(selection: $imageViewerSelection)
    }

    /// One layout for both sizes, so the photo keeps its identity and resizes with the
    /// keyboard instead of being swapped for a thumbnail.
    private func stagedPhoto(_ image: UIImage) -> some View {
        let layout = isCompact
            ? AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
            : AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space8))
        return layout {
            photo(image)
            HStack(spacing: PaeoniaSpacing.space8) {
                libraryButton
                if isCompact {
                    removeButton.transition(.dailyComposerFold)
                } else {
                    Spacer(minLength: 0)
                    cameraButton.transition(.dailyComposerFold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func photo(_ image: UIImage) -> some View {
        Button { show(image) } label: {
            Rectangle()
                .fill(colors.control)
                .frame(width: isCompact ? 44 : nil, height: isCompact ? 44 : previewHeight)
                .overlay {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: isCompact ? PaeoniaRadius.radius8 : PaeoniaRadius.radius12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.dailyChallengePhotoAnswerAccessibility))
        // Faded rather than removed, so it stays on the corner of the shrinking photo.
        .overlay(alignment: .topTrailing) {
            removeButton
                .background(.paeoniaBackgroundSecondary.opacity(0.92), in: Circle())
                .padding(PaeoniaSpacing.space8)
                .opacity(isCompact ? 0 : 1)
                .allowsHitTesting(!isCompact)
                .accessibilityHidden(isCompact)
        }
        .overlay { busyOverlay }
    }

    private var libraryButton: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Label {
                if !isCompact { Text(.dailyChallengePhotoChange) }
            } icon: {
                Image(systemName: "photo.on.rectangle")
            }
            .font(PaeoniaTypography.caption)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.accent)
        .disabled(isBusy)
        .accessibilityLabel(Text(.dailyChallengePhotoChange))
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.foreground)
        .disabled(isBusy)
        .accessibilityLabel(Text(.dailyChallengePhotoRemove))
        .accessibilityIdentifier("daily.answer.photo.remove")
    }

    private var picker: some View {
        let label = DailyPhotoPickerLabel(isBusy: isBusy, isCompact: isCompact)
        return HStack(spacing: PaeoniaSpacing.space8) {
            PhotosPicker(selection: $selection, matching: .images) { label }
                .buttonStyle(.plain)
                .disabled(isBusy)
            cameraButton
        }
    }

    @ViewBuilder
    private var cameraButton: some View {
        if DailyCameraPicker.isAvailable {
            Button { isCameraPresented = true } label: {
                Image(systemName: "camera").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.accent)
            .disabled(isBusy)
            .accessibilityLabel(Text(.dailyChallengePhotoTake))
        }
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ProgressView()
                .tint(colors.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.paeoniaBackgroundSecondary.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        }
    }

    private func show(_ image: UIImage) {
        imageViewerSelection = PaeoniaImageViewerSelection(image: image)
    }

    private func loadSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoading = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                onPick(data)
            } else {
                onPickFailed()
            }
            isLoading = false
            selection = nil
        }
    }
}

private struct DailyPhotoPickerLabel: View {
    let isBusy: Bool
    let isCompact: Bool
    @Environment(\.dailyAnswerComposerColors) private var colors

    var body: some View {
        Label {
            Text(.dailyChallengePhotoLabel)
        } icon: {
            Image(systemName: "photo.badge.plus")
        }
        .font(PaeoniaTypography.body)
        .foregroundStyle(colors.foreground)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 44 : 104)
        .background(colors.control, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        .overlay {
            if isBusy { ProgressView().tint(colors.accent) }
        }
    }
}
