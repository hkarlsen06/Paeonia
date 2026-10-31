import Observation
import UIKit

/// The selected page's existing scroll view. Native controls and gestures use
/// the same zoom and pan state; changing pages cannot operate the previous photo.
@MainActor
@Observable
final class PaeoniaImageZoomController {
    private(set) var scale: CGFloat = 1
    private(set) var isAvailable = false
    private(set) var maximumScale: CGFloat = 4
    @ObservationIgnored private weak var scrollView: UIScrollView?
    @ObservationIgnored private weak var coordinator: PaeoniaZoomableImageView.Coordinator?

    var canZoomIn: Bool { isAvailable && scale < maximumScale - 0.01 }
    var canZoomOut: Bool { isAvailable && scale > 1.01 }

    func bind(_ scrollView: UIScrollView, coordinator: PaeoniaZoomableImageView.Coordinator) {
        self.scrollView = scrollView
        self.coordinator = coordinator
        // UIKit can lay out or reset while SwiftUI updates its adapter. Publish
        // after that update, and discard callbacks from an old page.
        Task { @MainActor [weak self, weak scrollView] in
            guard let self, let scrollView, self.scrollView === scrollView else { return }
            scale = scrollView.zoomScale
            maximumScale = scrollView.maximumZoomScale
            isAvailable = scrollView.bounds.width > 0 && scrollView.bounds.height > 0
                && coordinator.imageView.bounds.width > 0
        }
    }

    func release(_ scrollView: UIScrollView) {
        guard self.scrollView === scrollView else { return }
        self.scrollView = nil
        coordinator = nil
        Task { @MainActor [weak self] in
            guard let self, self.scrollView == nil else { return }
            scale = 1
            isAvailable = false
        }
    }

    func clear() {
        scrollView = nil
        coordinator = nil
        scale = 1
        isAvailable = false
    }

    func zoomIn() { zoom(to: scale * 2) }
    func zoomOut() { zoom(to: scale / 2) }

    private func zoom(to scale: CGFloat) {
        guard isAvailable, let scrollView, let coordinator else { return }
        coordinator.zoom(to: scale, in: scrollView)
    }

    func fit() {
        guard isAvailable, let scrollView, let coordinator else { return }
        coordinator.resetZoom(in: scrollView, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func pan(horizontal: CGFloat, vertical: CGFloat) {
        guard canZoomOut, let scrollView else { return }
        let minX = -scrollView.adjustedContentInset.left
        let minY = -scrollView.adjustedContentInset.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width
                       + scrollView.adjustedContentInset.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height
                       + scrollView.adjustedContentInset.bottom)
        let offset = CGPoint(
            x: min(maxX, max(minX, scrollView.contentOffset.x + horizontal * scrollView.bounds.width * 0.45)),
            y: min(maxY, max(minY, scrollView.contentOffset.y + vertical * scrollView.bounds.height * 0.45))
        )
        scrollView.setContentOffset(offset, animated: !UIAccessibility.isReduceMotionEnabled)
    }
}
