import AVKit
import UIKit

/// Keeps the partner's video going in system Picture in Picture when the app goes to the
/// background during a video call. Inside the app the floating bubble shows the call instead.
final class CallPictureInPicture {
    private let contentController = AVPictureInPictureVideoCallViewController()
    private var controller: AVPictureInPictureController?
    /// The partner's video on screen, which the system animates into Picture in Picture.
    private weak var sourceView: UIView?
    private var isEnabled = false

    init(feed: CallVideoFeed) {
        let video = feed.makeView()
        video.translatesAutoresizingMaskIntoConstraints = false
        contentController.view.addSubview(video)
        NSLayoutConstraint.activate([
            video.leadingAnchor.constraint(equalTo: contentController.view.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: contentController.view.trailingAnchor),
            video.topAnchor.constraint(equalTo: contentController.view.topAnchor),
            video.bottomAnchor.constraint(equalTo: contentController.view.bottomAnchor),
        ])
        feed.onFrameSize = { [weak self] size in
            self?.contentController.preferredContentSize = size
        }
    }

    /// Picture in Picture may start while the partner's camera is on during a call.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            controller?.stopPictureInPicture()
        }
        update()
    }

    /// A view showing the partner's video entered or left a window.
    func sourceViewChanged(_ view: UIView) {
        if view.window != nil {
            sourceView = view
        } else if view === sourceView {
            sourceView = nil
        }
        update()
    }

    private func update() {
        guard isEnabled, AVPictureInPictureController.isPictureInPictureSupported(),
              let sourceView, sourceView.window != nil
        else {
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
            return
        }
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentController
        )
        if let controller {
            controller.contentSource = source
        } else {
            controller = AVPictureInPictureController(contentSource: source)
        }
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
    }
}
