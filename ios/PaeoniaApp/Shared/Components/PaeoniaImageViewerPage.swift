import SwiftUI
import UIKit

struct PaeoniaImageViewerPage: View {
    let item: PaeoniaImageViewerItem
    let isSelected: Bool
    let zoomControls: PaeoniaImageZoomController
    let onZoomStateChanged: (Bool) -> Void
    let onFailureChanged: (Bool) -> Void

    @State private var image: UIImage?
    @State private var failure: PaeoniaFailure?
    @State private var loadAttempt = 0

    init(
        item: PaeoniaImageViewerItem,
        isSelected: Bool,
        zoomControls: PaeoniaImageZoomController,
        onZoomStateChanged: @escaping (Bool) -> Void,
        onFailureChanged: @escaping (Bool) -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.zoomControls = zoomControls
        self.onZoomStateChanged = onZoomStateChanged
        self.onFailureChanged = onFailureChanged
        _image = State(initialValue: item.image)
    }

    var body: some View {
        ZStack {
            if let image {
                PaeoniaZoomableImageView(
                    image: image,
                    isActive: isSelected,
                    controls: zoomControls,
                    onZoomStateChanged: onZoomStateChanged
                )
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(Text(verbatim: PhotoDescription.label(item.accessibilityText)))
                .accessibilityIdentifier("imageViewer.photo")
                .accessibilityIgnoresInvertColors()
            } else if let failure {
                PaeoniaImageViewerLoadFailure(
                    failure: failure, description: item.accessibilityText,
                    retry: { loadAttempt += 1 }
                )
            } else {
                ProgressView()
                    .tint(.white.opacity(0.8))
                    .accessibilityLabel(Text(.imageViewerLoading))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(!isSelected)
        .contentShape(Rectangle())
        .task(id: loadAttempt) { await loadImageIfNeeded() }
        .onChange(of: failure, initial: true) { _, failure in onFailureChanged(failure != nil) }
        .onChange(of: isSelected) { _, newValue in
            if !newValue {
                onZoomStateChanged(false)
            }
        }
    }

    private func loadImageIfNeeded() async {
        guard image == nil else { return }
        failure = nil
        guard let imageLoader = item.imageLoader else {
            failure = .other
            return
        }
        do {
            let loadedImage = try await imageLoader()
            guard !Task.isCancelled else { return }
            if let loadedImage { image = loadedImage }
            else { failure = .other }
        } catch {
            guard !Task.isCancelled else { return }
            failure = PaeoniaFailure(error)
        }
    }
}
