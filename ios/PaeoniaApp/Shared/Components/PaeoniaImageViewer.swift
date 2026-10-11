import SwiftUI
import UIKit

struct PaeoniaImageViewerItem: Identifiable {
    let id: String
    let image: UIImage?
    let imageLoader: (@Sendable () async -> UIImage?)?

    init(id: String = UUID().uuidString, image: UIImage) {
        self.id = id
        self.image = image
        self.imageLoader = nil
    }

    init(id: UUID, image: UIImage) {
        self.id = id.uuidString
        self.image = image
        self.imageLoader = nil
    }

    init(
        id: String,
        image: UIImage? = nil,
        imageLoader: @escaping @Sendable () async -> UIImage?
    ) {
        self.id = id
        self.image = image
        self.imageLoader = imageLoader
    }

    init(
        id: UUID,
        image: UIImage? = nil,
        imageLoader: @escaping @Sendable () async -> UIImage?
    ) {
        self.id = id.uuidString
        self.image = image
        self.imageLoader = imageLoader
    }
}

struct PaeoniaImageViewerSelection: Identifiable {
    let id = UUID()
    let items: [PaeoniaImageViewerItem]
    let initialItemID: String
    /// Shows a button that saves the photo on screen to the photo library.
    var allowsSaving = false

    init(items: [PaeoniaImageViewerItem], initialItemID: String, allowsSaving: Bool = false) {
        self.items = items
        self.initialItemID = initialItemID
        self.allowsSaving = allowsSaving
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
    var allowsSaving = false
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItemID: String
    @State private var savedItemIDs: Set<String> = []
    @State private var isSaving = false
    @State private var selectedPageIsZoomed = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @State private var containerHeight: CGFloat = 800
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
        allowsSaving: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.items = items
        self.initialItemID = initialItemID
        self.allowsSaving = allowsSaving
        self.onDismiss = onDismiss
        _selectedItemID = State(initialValue: initialItemID)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dragProgress)
                .ignoresSafeArea()

            if items.isEmpty {
                Color.clear
                    .onAppear { onDismiss() }
            } else {
                pages
            }

            VStack {
                topBar
                    .padding(.horizontal, PaeoniaSpacing.space20)
                    .padding(.top, PaeoniaSpacing.space20)

                Spacer()

                pageIndicator
                    .padding(.bottom, PaeoniaSpacing.space32)
            }
            .opacity(1 - dragProgress)
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom
        } action: {
            containerHeight = $0
        }
        .accessibilityAction(.escape) { onDismiss() }
        .simultaneousGesture(verticalDismissGesture)
        .onChange(of: isDragging) { _, dragging in
            if !dragging, !isDismissing { settleBack() }
        }
        .onChange(of: selectedItemID) { _, _ in
            selectedPageIsZoomed = false
        }
        .statusBarHidden()
    }

    private var pages: some View {
        TabView(selection: $selectedItemID) {
            ForEach(items) { item in
                PaeoniaImageViewerPage(
                    item: item,
                    isSelected: item.id == selectedItemID,
                    onZoomStateChanged: { isZoomed in
                        if item.id == selectedItemID {
                            selectedPageIsZoomed = isZoomed
                        }
                    }
                )
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .offset(y: dragOffset)
    }

    private var topBar: some View {
        HStack {
            if allowsSaving {
                saveButton
            }
            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.32)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.commonClose))
        }
        .padding(.vertical, PaeoniaSpacing.space4)
    }

    /// Saves the photo on screen to the photo library. The icon turns into a check once
    /// it's saved, like Tidex's gallery.
    private var saveButton: some View {
        let isSaved = savedItemIDs.contains(selectedItemID)
        return Button {
            Task { await saveSelectedImage() }
        } label: {
            Image(systemName: isSaved ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.32)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isSaved)
        .accessibilityLabel(Text(isSaved ? .imageViewerSaved : .imageViewerSave))
    }

    private func saveSelectedImage() async {
        guard let item = items.first(where: { $0.id == selectedItemID }) else { return }
        isSaving = true
        defer { isSaving = false }
        var loaded = item.image
        if loaded == nil { loaded = await item.imageLoader?() }
        guard let data = loaded?.pngData() else { return }
        if await PhotoLibrarySaver().savePNG(data) == .saved {
            savedItemIDs.insert(item.id)
            PaeoniaHaptics.selection()
        }
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if let selectedIndex, items.count > 1 {
            Text(.imageViewerPageCounter((selectedIndex + 1).formatted(), items.count.formatted()))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.35)))
                .allowsHitTesting(false)
        }
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
                    flyOffAndDismiss()
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

    /// Slides the photo off the bottom while the backdrop fades, then dismisses.
    /// With Reduce Motion it dismisses straight away.
    private func flyOffAndDismiss() {
        isDismissing = true
        guard !reduceMotion else {
            onDismiss()
            return
        }

        withAnimation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionDefault)) {
            dragOffset = containerHeight
        } completion: {
            // The photo is already gone, so skip the cover's own slide-down.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { onDismiss() }
        }
    }
}

extension View {
    func paeoniaImageViewer(selection: Binding<PaeoniaImageViewerSelection?>) -> some View {
        fullScreenCover(item: selection) { viewerSelection in
            PaeoniaImageViewerOverlay(
                items: viewerSelection.items,
                initialItemID: viewerSelection.initialItemID,
                allowsSaving: viewerSelection.allowsSaving
            ) {
                selection.wrappedValue = nil
            }
            // The backdrop fades during a drag, so the cover must not add its own.
            .presentationBackground(.clear)
        }
    }
}

private struct PaeoniaImageViewerPage: View {
    let item: PaeoniaImageViewerItem
    let isSelected: Bool
    let onZoomStateChanged: (Bool) -> Void

    @State private var image: UIImage?
    @State private var didFail = false

    init(
        item: PaeoniaImageViewerItem,
        isSelected: Bool,
        onZoomStateChanged: @escaping (Bool) -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onZoomStateChanged = onZoomStateChanged
        _image = State(initialValue: item.image)
    }

    var body: some View {
        ZStack {
            if let image {
                PaeoniaZoomableImageView(
                    image: image,
                    isActive: isSelected,
                    onZoomStateChanged: onZoomStateChanged
                )
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityIgnoresInvertColors()
            } else if didFail {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .tint(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .task(id: item.id) { await loadImageIfNeeded() }
        .onChange(of: isSelected) { _, newValue in
            if !newValue {
                onZoomStateChanged(false)
            }
        }
    }

    private func loadImageIfNeeded() async {
        guard image == nil, let imageLoader = item.imageLoader else {
            return
        }

        if let loadedImage = await imageLoader() {
            image = loadedImage
        } else {
            didFail = true
        }
    }
}
