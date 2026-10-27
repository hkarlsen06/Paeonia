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
    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var isCameraPresented = false
    @State private var imageViewerSelection: PaeoniaImageViewerSelection?

    private var isBusy: Bool { isLoading || isPreparing }

    var body: some View {
        Group {
            if let imageData {
                DailyDecodedPhoto(data: imageData, reservedHeight: isCompact ? 44 : previewHeight) { image in
                    if isCompact {
                        compactPhoto(image)
                    } else {
                        fullPhoto(image)
                    }
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

    private func compactPhoto(_ image: UIImage) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Button { show(image) } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.dailyChallengePhotoAnswerAccessibility))

            Text(.dailyChallengeComposerPhotoAdded)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(colors.foreground)
            Spacer(minLength: 0)
            libraryButton
            removeButton
        }
        .overlay { busyOverlay }
    }

    private func fullPhoto(_ image: UIImage) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Rectangle()
                .fill(colors.control)
                .frame(height: previewHeight)
                .overlay {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
                .contentShape(Rectangle())
                .onTapGesture { show(image) }
                .accessibilityLabel(Text(.dailyChallengePhotoAnswerAccessibility))
                .accessibilityAddTraits(.isButton)
                .overlay(alignment: .topTrailing) {
                    removeButton
                        .background(.paeoniaBackgroundSecondary.opacity(0.92), in: Circle())
                        .padding(PaeoniaSpacing.space8)
                }
                .overlay { busyOverlay }

            HStack {
                libraryButton
                Spacer(minLength: 0)
                cameraButton
            }
        }
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
