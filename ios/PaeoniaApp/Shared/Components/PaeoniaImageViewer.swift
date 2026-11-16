import Photos
import SwiftUI
import UIKit

struct PaeoniaImageViewerItem: Identifiable {
    var accessibilityText: String?
    let id: String
    let image: UIImage?
    let imageLoader: (@Sendable () async throws -> UIImage?)?
    /// Set for an animated GIF. Its page plays the bytes, and Save keeps them, so the
    /// saved GIF still moves.
    var animatedDataLoader: (@Sendable () async throws -> Data?)?

    init(id: String = UUID().uuidString, image: UIImage, accessibilityText: String? = nil) {
        self.id = id
        self.accessibilityText = accessibilityText
        self.image = image
        self.imageLoader = nil
    }

    init(id: UUID, image: UIImage, accessibilityText: String? = nil) {
        self.id = id.uuidString
        self.accessibilityText = accessibilityText
        self.image = image
        self.imageLoader = nil
    }

    init(
        id: String,
        image: UIImage? = nil,
        accessibilityText: String? = nil,
        imageLoader: @escaping @Sendable () async throws -> UIImage?
    ) {
        self.id = id
        self.accessibilityText = accessibilityText
        self.image = image
        self.imageLoader = imageLoader
    }

    init(
        id: UUID,
        image: UIImage? = nil,
        accessibilityText: String? = nil,
        imageLoader: @escaping @Sendable () async throws -> UIImage?
    ) {
        self.id = id.uuidString
        self.accessibilityText = accessibilityText
        self.image = image
        self.imageLoader = imageLoader
    }
}

extension PaeoniaImageViewerItem {
    /// An animated GIF, played one frame at a time. It does not zoom.
    init(
        id: String,
        accessibilityText: String? = nil,
        animatedDataLoader: @escaping @Sendable () async throws -> Data?
    ) {
        self.id = id
        self.accessibilityText = accessibilityText
        self.image = nil
        self.imageLoader = nil
        self.animatedDataLoader = animatedDataLoader
    }
}

struct PaeoniaImageViewerSelection: Identifiable {
    let id = UUID()
    let items: [PaeoniaImageViewerItem]
    let initialItemID: String

    init(items: [PaeoniaImageViewerItem], initialItemID: String) {
        self.items = items
        self.initialItemID = initialItemID
    }

    init(id: String = UUID().uuidString, image: UIImage) {
        self.items = [PaeoniaImageViewerItem(id: id, image: image)]
        self.initialItemID = id
    }

    init(id: UUID, image: UIImage) {
        self.init(id: id.uuidString, image: image)
    }
}

struct PaeoniaImageViewerOverlay: View {
    let items: [PaeoniaImageViewerItem]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @AccessibilityPresentation(.controls) private var showsControls
    @State private var selectedItemID: String
    @State private var savedItemIDs: Set<String> = []
    @State private var isSaving = false
    @State private var isShowingSavePermissionAlert = false
    @State private var selectedPageIsZoomed = false
    @State private var failedItemIDs: Set<String> = []
    @State private var zoomControls = PaeoniaImageZoomController()
    @State private var controlsHeight: CGFloat = 200
    @State private var bannerCenter = PaeoniaBannerCenter()
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    /// Resets to false when the drag ends or the system cancels it, so a cancelled
    /// drag still settles back even though `onEnded` never runs.
    @GestureState private var isDragging = false

    private static let dismissDistance: CGFloat = 120
    private static let flickDistance: CGFloat = 30
    private static let flickPredictedDistance: CGFloat = 350
    private static let fadeDistance: CGFloat = 400

    init(
        items: [PaeoniaImageViewerItem],
        initialItemID: String,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self.onDismiss = onDismiss
        _selectedItemID = State(initialValue: initialItemID)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(1 - dragProgress)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, PaeoniaSpacing.space20)
                        .padding(.top, PaeoniaSpacing.space20)
                        .opacity(1 - dragProgress)
                    if items.isEmpty {
                        Color.clear.onAppear { onDismiss() }
                    } else {
                        pages
                    }
                    if showsControls {
                        controls(maxHeight: geometry.size.height / 2)
                            .opacity(1 - dragProgress)
                    }
                }
            }
        }
        .accessibilityAction(.escape) { onDismiss() }
        .onChange(of: isDragging) { _, dragging in
            if !dragging, !isDismissing { settleBack() }
        }
        .onChange(of: selectedItemID) { _, _ in
            selectedPageIsZoomed = false
        }
        .statusBarHidden()
        .paeoniaBanner(bannerCenter)
        .alert(Text(.imageViewerSavePermissionTitle), isPresented: $isShowingSavePermissionAlert) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.commonOpenSettings)
            }

            Button(role: .cancel) {} label: {
                Text(.commonCancel)
            }
        } message: {
            Text(.imageViewerSavePermissionMessage)
        }
    }

    /// At large text sizes or in a short window, controls scroll within their
    /// own space while the fitted photo remains visible above them.
    private func controls(maxHeight: CGFloat) -> some View {
        ScrollView {
            PaeoniaImageViewerControls(
                index: selectedIndex, count: items.count, zoom: zoomControls,
                previous: { changePage(by: -1) }, next: { changePage(by: 1) }
            )
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(controlsHeight, maxHeight))
    }

    private var pages: some View {
        TabView(selection: $selectedItemID) {
            ForEach(items) { item in
                Group {
                    if let animatedDataLoader = item.animatedDataLoader {
                        PaeoniaAnimatedImageViewerPage(
                            item: item,
                            loader: animatedDataLoader,
                            isSelected: item.id == selectedItemID,
                            onFailureChanged: { failed in pageFailureChanged(item.id, failed: failed) }
                        )
                    } else {
                        PaeoniaImageViewerPage(
                            item: item,
                            isSelected: item.id == selectedItemID,
                            zoomControls: zoomControls,
                            onZoomStateChanged: { isZoomed in
                                if item.id == selectedItemID {
                                    selectedPageIsZoomed = isZoomed
                                }
                            },
                            onFailureChanged: { failed in pageFailureChanged(item.id, failed: failed) }
                        )
                    }
                }
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .offset(y: dragOffset)
        .simultaneousGesture(
            verticalDismissGesture, including: failedItemIDs.contains(selectedItemID) ? .subviews : .all
        )
    }

    private func pageFailureChanged(_ itemID: String, failed: Bool) {
        if failed { failedItemIDs.insert(itemID) }
        else { failedItemIDs.remove(itemID) }
    }

    private var topBar: some View {
        HStack {
            PaeoniaViewerSaveButton(
                isSaving: isSaving,
                isSaved: savedItemIDs.contains(selectedItemID),
                accessibilityIdentifier: "imageViewer.save"
            ) {
                Task { await saveSelectedImage() }
            }
            Spacer()
            PaeoniaViewerCloseButton(accessibilityIdentifier: "imageViewer.close", action: onDismiss)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
    }

    private func changePage(by offset: Int) {
        guard let index = selectedIndex, items.indices.contains(index + offset) else { return }
        zoomControls.clear()
        selectedItemID = items[index + offset].id
    }

    private var selectedIndex: Int? {
        items.firstIndex(where: { $0.id == selectedItemID })
    }

    /// 0 at rest, 1 once the image has moved `fadeDistance` down.
    private var dragProgress: CGFloat {
        min(max(dragOffset, 0) / Self.fadeDistance, 1)
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                guard !selectedPageIsZoomed, !isDismissing else { return }
                dragOffset = Self.isDownwardDrag(value.translation) ? value.translation.height : 0
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let translation = value.translation
                if !selectedPageIsZoomed,
                   Self.isDownwardDrag(translation),
                   Self.shouldDismiss(
                       distance: translation.height,
                       predictedDistance: value.predictedEndTranslation.height
                   ) {
                    dismissAfterDrag()
                } else {
                    settleBack()
                }
            }
    }

    private static func isDownwardDrag(_ translation: CGSize) -> Bool {
        translation.height > 0 && translation.height > abs(translation.width)
    }

    /// A long drag dismisses. So does a short, fast flick, judged by where the
    /// drag would end if it kept its speed.
    private static func shouldDismiss(distance: CGFloat, predictedDistance: CGFloat) -> Bool {
        distance >= dismissDistance
            || (distance >= flickDistance && predictedDistance >= flickPredictedDistance)
    }

    private func settleBack() {
        guard dragOffset != 0 else { return }
        let animation: Animation = reduceMotion
            ? PaeoniaMotion.buttonPress
            : .spring(duration: PaeoniaMotion.motionSlow, bounce: 0.15)
        withAnimation(animation) { dragOffset = 0 }
    }

    /// Dismiss through the native cover immediately. Navigation does not wait for animation completion.
    private func dismissAfterDrag() {
        isDismissing = true
        var transaction = Transaction()
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) { onDismiss() }
    }

}

extension PaeoniaImageViewerOverlay {
    private func saveSelectedImage() async {
        guard let item = items.first(where: { $0.id == selectedItemID }) else { return }
        isSaving = true
        defer { isSaving = false }
        var loaded = item.image
        var animatedData: Data?
        do {
            if let animatedDataLoader = item.animatedDataLoader {
                animatedData = try await animatedDataLoader()
            } else if loaded == nil {
                loaded = try await item.imageLoader?()
            }
        } catch {
            guard !Task.isCancelled else { return }
            showSaveFailure(PaeoniaFailure(error))
            return
        }
        guard !Task.isCancelled else { return }
        guard let data = animatedData ?? loaded?.pngData() else {
            showSaveFailure(.other)
            return
        }
        handleSaveResult(await PhotoLibrarySaver().saveImage(data), itemID: item.id)
    }

    private func handleSaveResult(_ result: PhotoLibrarySaveResult, itemID: String) {
        switch result {
        case .saved:
            savedItemIDs.insert(itemID)
            bannerCenter.show(
                .info(message: String(localized: .imageViewerSaved), systemImage: "square.and.arrow.down")
            )
        case .permissionDenied:
            showPhotoPermissionFailure()
        case .failed:
            showSaveFailure(.other)
        }
    }

    private func showPhotoPermissionFailure() {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .denied:
            isShowingSavePermissionAlert = true
        case .restricted:
            bannerCenter.show(.error(message: String(localized: .imageViewerSaveRestricted)))
        default:
            showSaveFailure(.other)
        }
    }

    private func showSaveFailure(_ failure: PaeoniaFailure) {
        bannerCenter.show(.error(message: String(localized:
            failure == .offline ? .imageViewerSaveOffline : .imageViewerSaveFailed
        )))
    }
}

extension View {
    func paeoniaImageViewer(selection: Binding<PaeoniaImageViewerSelection?>) -> some View {
        fullScreenCover(item: selection) { viewerSelection in
            PaeoniaImageViewerOverlay(
                items: viewerSelection.items,
                initialItemID: viewerSelection.initialItemID
            ) {
                selection.wrappedValue = nil
            }
            // Keep the underlying screen visible as the dragged backdrop fades.
            .presentationBackground(.clear)
        }
    }
}

/// A GIF's page. It plays one frame at a time and does not zoom.
private struct PaeoniaAnimatedImageViewerPage: View {
    let item: PaeoniaImageViewerItem
    let loader: @Sendable () async throws -> Data?
    let isSelected: Bool
    let onFailureChanged: (Bool) -> Void

    @State private var data: Data?
    @State private var failure: PaeoniaFailure?
    @State private var loadAttempt = 0

    var body: some View {
        ZStack {
            if let data {
                AnimatedImageView(
                    id: item.id,
                    data: data,
                    accessibilityLabel: Text(verbatim: PhotoDescription.label(item.accessibilityText)),
                    contentMode: .fit
                )
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
        .task(id: loadAttempt) { await load() }
        .onChange(of: failure, initial: true) { _, failure in onFailureChanged(failure != nil) }
    }

    private func load() async {
        guard data == nil else { return }
        failure = nil
        do {
            let loaded = try await loader()
            guard !Task.isCancelled else { return }
            if let loaded { data = loaded } else { failure = .other }
        } catch {
            guard !Task.isCancelled else { return }
            failure = PaeoniaFailure(error)
        }
    }
}
