import AVKit
import UIKit

/// Keeps the partner's video going in system Picture in Picture when the app goes to the
/// background during a video call, or their shared screen while they share it. Inside the app the
/// floating bubble shows the call instead.
final class CallPictureInPicture {
    private let contentController = AVPictureInPictureVideoCallViewController()
    private var controller: AVPictureInPictureController?
    /// The window's content. Showing the other one keeps the running Picture in Picture and its
    /// source, which a new source would end.
    private let cameraView: UIView
    private let screenView: UIView
    private var shown = CallVideoSource.partner
    /// The upright size of each one's latest frame.
    private var videoSizes: [CallVideoSource: CGSize] = [:]
    /// Every view showing the partner's video or screen, such as the call screen's and the bubble's.
    private var partnerViews: [WeakView] = []
    /// The partner's video the person sees, which the system animates into Picture in Picture.
    private weak var sourceView: UIView?
    private var isEnabled = false
    private var resignObserver: (any NSObjectProtocol)?
    private var activeObserver: (any NSObjectProtocol)?

    init(partner: CallVideoFeed, partnerScreen: CallVideoFeed) {
        cameraView = partner.makeView()
        screenView = partnerScreen.makeView()
        screenView.isHidden = true
        for video in [cameraView, screenView] {
            video.translatesAutoresizingMaskIntoConstraints = false
            contentController.view.addSubview(video)
            NSLayoutConstraint.activate([
                video.leadingAnchor.constraint(equalTo: contentController.view.leadingAnchor),
                video.trailingAnchor.constraint(equalTo: contentController.view.trailingAnchor),
                video.topAnchor.constraint(equalTo: contentController.view.topAnchor),
                video.bottomAnchor.constraint(equalTo: contentController.view.bottomAnchor),
            ])
        }
        // The call screen and the bubble swap with animations that end after the last change
        // to window membership, so the source is chosen once more just before the app leaves.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // Inside the app the bubble shows the call. iOS can leave Picture in Picture on screen when
        // the person comes back, next to the bubble, so it closes here.
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let controller = self?.controller, controller.isPictureInPictureActive else { return }
                controller.stopPictureInPicture()
            }
        }
    }

    /// The upright size of the partner's frames, which Picture in Picture's window takes while it
    /// shows them.
    func setVideoSize(_ size: CGSize, of source: CallVideoSource) {
        videoSizes[source] = size
        if source == shown {
            contentController.preferredContentSize = size
        }
    }

    /// Shows the partner's camera or their shared screen in the window.
    func show(_ source: CallVideoSource) {
        guard source != shown else { return }
        shown = source
        cameraView.isHidden = source != .partner
        screenView.isHidden = source != .partnerScreen
        contentController.preferredContentSize = videoSizes[source] ?? .zero
    }

    /// Picture in Picture may start while the partner's camera is on, or their screen is shared,
    /// during a call. The engine calls this on every change to the call, which also chooses the
    /// source again.
    func setEnabled(_ enabled: Bool) {
        if isEnabled, !enabled {
            // `stopPictureInPicture()` does nothing while the app is in the background, where
            // the window cannot animate back into the app. Releasing the controller stops it
            // there too, and `update()` makes a new one once Picture in Picture may start again.
            controller = nil
        }
        isEnabled = enabled
        update()
    }

    /// A new view showing the partner's video or screen. Its source follows the views on screen.
    func track(_ view: CallVideoLayerView) {
        partnerViews.removeAll { $0.view == nil }
        partnerViews.append(WeakView(view: view))
        view.onWindowChange = { [weak self] in self?.update() }
    }

    /// Points Picture in Picture at the partner's video the person sees. A view can stay in a
    /// window while another covers it, or while it fades or moves away, so being in a window
    /// is not enough.
    private func update() {
        guard isEnabled, AVPictureInPictureController.isPictureInPictureSupported() else {
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
            return
        }
        // Changing the source of a running Picture in Picture would end it.
        guard controller?.isPictureInPictureActive != true else { return }
        partnerViews.removeAll { $0.view == nil }
        guard let visible = partnerViews.compactMap(\.view).filter(Self.isVisible).max(by: {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }) else {
            sourceView = nil
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
            return
        }
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        guard visible !== sourceView || controller == nil else { return }
        sourceView = visible
        // AVKit watches only the view a controller was made with. Given a new `contentSource`, it
        // never sees the new view as visible and Picture in Picture cannot start, so a new
        // controller takes over. The old one goes first, since both share `contentController`.
        controller = nil
        controller = AVPictureInPictureController(contentSource: .init(
            activeVideoCallSourceView: visible,
            contentViewController: contentController
        ))
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    /// In a shown window, not hidden or transparent anywhere up to it, and at least partly on it.
    private static func isVisible(_ view: UIView) -> Bool {
        guard let window = view.window, !view.bounds.isEmpty else { return false }
        var alpha: CGFloat = 1
        var current: UIView? = view
        while let ancestor = current {
            guard !ancestor.isHidden else { return false }
            alpha *= ancestor.alpha
            current = ancestor.superview
        }
        return alpha > 0.01 && view.convert(view.bounds, to: window).intersects(window.bounds)
    }

    private struct WeakView {
        weak var view: UIView?
    }
}
