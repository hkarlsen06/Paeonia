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

    @State private var selectedItemID: String
    @State private var selectedPageIsZoomed = false
    @GestureState private var dismissTranslationY: CGFloat = 0

    private let dismissThreshold: CGFloat = 120

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
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                Color.clear
                    .onAppear { onDismiss() }
            } else {
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
                .offset(y: currentDismissOffsetY)
            }

            VStack {
                topBar
                    .padding(.horizontal, PaeoniaSpacing.space20)
                    .padding(.top, PaeoniaSpacing.space20)

                Spacer()

                pageIndicator
                    .padding(.bottom, PaeoniaSpacing.space32)
            }
        }
        .simultaneousGesture(verticalDismissGesture)
        .onChange(of: selectedItemID) { _, _ in
            selectedPageIsZoomed = false
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.32)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.commonCancel))
        }
        .padding(.vertical, PaeoniaSpacing.space4)
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if let selectedIndex, items.count > 1 {
            Text("\(selectedIndex + 1) / \(items.count)")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.88))
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.35)))
                .allowsHitTesting(false)
        }
    }

    private var selectedIndex: Int? {
        items.firstIndex(where: { $0.id == selectedItemID })
    }

    private var currentDismissOffsetY: CGFloat {
        guard !selectedPageIsZoomed else { return 0 }
        return max(0, dismissTranslationY)
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dismissTranslationY) { value, state, _ in
                guard !selectedPageIsZoomed else { return }

                let horizontal = abs(value.translation.width)
                let vertical = value.translation.height

                guard vertical > 0, vertical > horizontal else { return }
                state = vertical
            }
            .onEnded { value in
                guard !selectedPageIsZoomed else { return }

                let horizontal = abs(value.translation.width)
                let vertical = value.translation.height

                guard vertical > 0, vertical > horizontal else { return }

                if vertical >= dismissThreshold {
                    onDismiss()
                }
            }
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
            } else if didFail {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
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

private struct PaeoniaZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isActive: Bool
    let onZoomStateChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomStateChanged: onZoomStateChanged)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.panGestureRecognizer.isEnabled = false

        let imageView = context.coordinator.imageView
        imageView.image = image
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)

        let doubleTapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapRecognizer)
        scrollView.onLayout = { [weak coordinator = context.coordinator] scrollView in
            coordinator?.layoutIfNeeded(in: scrollView)
        }
        context.coordinator.configure(image: image, in: scrollView, forceReset: true)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        context.coordinator.configure(image: image, in: scrollView, forceReset: !isActive)

        if !isActive, scrollView.zoomScale > scrollView.minimumZoomScale {
            context.coordinator.resetZoom(in: scrollView)
        }
    }

    private final class ZoomScrollView: UIScrollView {
        var onLayout: ((UIScrollView) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        var onZoomStateChanged: (Bool) -> Void

        private let minimumZoomEpsilon: CGFloat = 0.01
        private let minimumZoomSnapThreshold: CGFloat = 0.06
        private var currentImageIdentifier: ObjectIdentifier?
        private var lastBoundsSize: CGSize = .zero
        private var fittedImageSize: CGSize = .zero
        private var reportedIsZoomed = false
        private var isResettingZoom = false
        private var pendingImage: UIImage?

        init(onZoomStateChanged: @escaping (Bool) -> Void) {
            self.onZoomStateChanged = onZoomStateChanged
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let isZoomed = isZoomed(scrollView)
            scrollView.isScrollEnabled = isZoomed
            scrollView.panGestureRecognizer.isEnabled = isZoomed
            centerImage(in: scrollView)
            guard !isResettingZoom else { return }
            setZoomState(isZoomed)
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with _: UIView?,
            atScale scale: CGFloat
        ) {
            if scale <= scrollView.minimumZoomScale + minimumZoomSnapThreshold {
                resetZoom(in: scrollView)
                return
            }

            let isZoomed = scale > scrollView.minimumZoomScale + minimumZoomEpsilon
            scrollView.isScrollEnabled = isZoomed
            scrollView.panGestureRecognizer.isEnabled = isZoomed
            centerImage(in: scrollView)
            setZoomState(isZoomed)
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }

            if isZoomed(scrollView) {
                resetZoom(in: scrollView)
                return
            }

            let tapPoint = recognizer.location(in: imageView)
            let zoomScale = min(scrollView.maximumZoomScale, 2)
            let width = scrollView.bounds.size.width / zoomScale
            let height = scrollView.bounds.size.height / zoomScale
            let zoomRect = CGRect(
                x: tapPoint.x - (width / 2),
                y: tapPoint.y - (height / 2),
                width: width,
                height: height
            )
            scrollView.zoom(to: zoomRect, animated: true)
            scrollView.isScrollEnabled = true
            scrollView.panGestureRecognizer.isEnabled = true
            setZoomState(true)
        }

        func configure(image: UIImage, in scrollView: UIScrollView, forceReset: Bool) {
            pendingImage = image
            let imageIdentifier = ObjectIdentifier(image)
            let boundsSize = scrollView.bounds.size

            guard boundsSize.width > 0, boundsSize.height > 0 else {
                imageView.image = image
                return
            }

            let imageChanged = imageIdentifier != currentImageIdentifier
            let boundsChanged = boundsSize != lastBoundsSize

            guard imageChanged || boundsChanged || forceReset else {
                centerImage(in: scrollView)
                return
            }

            currentImageIdentifier = imageIdentifier
            lastBoundsSize = boundsSize
            imageView.image = image
            fittedImageSize = Self.fittedSize(for: image.size, in: boundsSize)

            if imageChanged || forceReset || !isZoomed(scrollView) {
                resetZoom(in: scrollView)
                return
            }

            imageView.frame = CGRect(origin: .zero, size: fittedImageSize)
            scrollView.contentSize = fittedImageSize
            centerImage(in: scrollView)
        }

        func layoutIfNeeded(in scrollView: UIScrollView) {
            guard let pendingImage else { return }
            configure(image: pendingImage, in: scrollView, forceReset: false)
        }

        func resetZoom(in scrollView: UIScrollView) {
            guard fittedImageSize.width > 0, fittedImageSize.height > 0 else { return }

            isResettingZoom = true
            defer { isResettingZoom = false }

            scrollView.contentInset = .zero
            scrollView.contentOffset = .zero
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 4
            scrollView.zoomScale = scrollView.minimumZoomScale
            imageView.transform = .identity
            imageView.frame = CGRect(origin: .zero, size: fittedImageSize)
            scrollView.contentSize = fittedImageSize
            centerImage(in: scrollView)
            scrollView.isScrollEnabled = false
            scrollView.panGestureRecognizer.isEnabled = false
            setZoomState(false)
        }

        private func centerImage(in scrollView: UIScrollView) {
            let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            imageView.center = CGPoint(
                x: scrollView.contentSize.width / 2 + horizontalInset,
                y: scrollView.contentSize.height / 2 + verticalInset
            )
        }

        private func isZoomed(_ scrollView: UIScrollView) -> Bool {
            scrollView.zoomScale > scrollView.minimumZoomScale + minimumZoomEpsilon
        }

        private func setZoomState(_ isZoomed: Bool) {
            guard reportedIsZoomed != isZoomed else { return }
            reportedIsZoomed = isZoomed
            onZoomStateChanged(isZoomed)
        }

        private static func fittedSize(for imageSize: CGSize, in boundsSize: CGSize) -> CGSize {
            guard imageSize.width > 0, imageSize.height > 0,
                  boundsSize.width > 0, boundsSize.height > 0
            else {
                return boundsSize
            }

            let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
            return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }
    }
}
