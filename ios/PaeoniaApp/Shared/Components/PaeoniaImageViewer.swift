import Photos
import SwiftUI
import UIKit

struct PaeoniaImageViewerItem: Identifiable {
    var accessibilityText: String?
    let id: String
    let image: UIImage?
    let imageLoader: (@Sendable () async throws -> UIImage?)?

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
    let initialItemID: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
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
    private static let controlBackground = Color.black.opacity(0.75)

    init(
        items: [PaeoniaImageViewerItem],
        initialItemID: String,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self.initialItemID = initialItemID
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
                    controls(maxHeight: geometry.size.height / 2)
                        .opacity(1 - dragProgress)
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
        .paeoniaTopBanner(bannerCenter)
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
                PaeoniaImageViewerPage(
                    item: item,
                    isSelected: item.id == selectedItemID,
                    zoomControls: zoomControls,
                    onZoomStateChanged: { isZoomed in
                        if item.id == selectedItemID {
                            selectedPageIsZoomed = isZoomed
                        }
                    },
                    onFailureChanged: { failed in
                        if failed { failedItemIDs.insert(item.id) }
                        else { failedItemIDs.remove(item.id) }
                    }
                )
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .offset(y: dragOffset)
        .simultaneousGesture(
            verticalDismissGesture, including: failedItemIDs.contains(selectedItemID) ? .subviews : .all
        )
    }

    private var topBar: some View {
        HStack {
            saveButton
            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Self.controlBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.commonClose))
            .accessibilityIdentifier("imageViewer.close")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
    }

    /// Saves the photo on screen to the photo library. It spins while saving and
    /// turns into a check once the photo is in Photos, like Tidex's gallery.
    private var saveButton: some View {
        let isSaved = savedItemIDs.contains(selectedItemID)
        return Button {
            Task { await saveSelectedImage() }
        } label: {
            ZStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isSaved)
                }
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(Self.controlBackground))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isSaved)
        .accessibilityLabel(Text(isSaved ? .imageViewerSaved : .imageViewerSave))
        .accessibilityIdentifier("imageViewer.save")
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
        do {
            if loaded == nil { loaded = try await item.imageLoader?() }
        } catch {
            guard !Task.isCancelled else { return }
            showSaveFailure(PaeoniaFailure(error))
            return
        }
        guard !Task.isCancelled else { return }
        guard let data = loaded?.pngData() else {
            showSaveFailure(.other)
            return
        }
        handleSaveResult(await PhotoLibrarySaver().saveImage(data), itemID: item.id)
    }

    private func handleSaveResult(_ result: PhotoLibrarySaveResult, itemID: String) {
        switch result {
        case .saved:
            savedItemIDs.insert(itemID)
            bannerCenter.show(.info(message: String(localized: .imageViewerSaved)))
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
