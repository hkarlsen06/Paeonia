import SwiftUI
import UIKit

/// Pinch and double-tap zoom for one photo in the full-screen viewer.
struct PaeoniaZoomableImageView: UIViewRepresentable {
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
        imageView.accessibilityIgnoresInvertColors = true
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
        context.coordinator.isActive = isActive
        context.coordinator.configure(image: image, in: scrollView, forceReset: true)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onZoomStateChanged = onZoomStateChanged

        // Reset only when the page stops being the selected one. Resetting on every
        // parent update would redo the layout on each frame of a drag.
        let deactivated = coordinator.isActive && !isActive
        coordinator.isActive = isActive
        coordinator.configure(image: image, in: scrollView, forceReset: deactivated)
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
        var isActive = true

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
            let animated = !UIAccessibility.isReduceMotionEnabled

            if isZoomed(scrollView) {
                resetZoom(in: scrollView, animated: animated)
                return
            }

            let zoomScale = min(scrollView.maximumZoomScale, 2)
            let zoomRect = zoomRect(
                around: recognizer.location(in: imageView),
                scale: zoomScale,
                in: scrollView
            )
            scrollView.zoom(to: zoomRect, animated: animated)
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

        /// Returns to the fitted size. With `animated`, the zoom eases out and the
        /// scroll view delegate callbacks finish the reset once the scale reaches 1.
        func resetZoom(in scrollView: UIScrollView, animated: Bool = false) {
            guard fittedImageSize.width > 0, fittedImageSize.height > 0 else { return }

            if animated, isZoomed(scrollView) {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

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

        /// A zoom target centered on `point` (in image view coordinates) that stays
        /// inside the displayed image, so a tap in the empty bars around a photo
        /// still zooms into the photo.
        private func zoomRect(around point: CGPoint, scale: CGFloat, in scrollView: UIScrollView) -> CGRect {
            let imageBounds = imageView.bounds
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            return CGRect(
                x: Self.clampedOrigin(point.x - size.width / 2, length: size.width, limit: imageBounds.width),
                y: Self.clampedOrigin(point.y - size.height / 2, length: size.height, limit: imageBounds.height),
                width: size.width,
                height: size.height
            )
        }

        private static func clampedOrigin(_ origin: CGFloat, length: CGFloat, limit: CGFloat) -> CGFloat {
            guard length < limit else { return (limit - length) / 2 }
            return min(max(origin, 0), limit - length)
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
