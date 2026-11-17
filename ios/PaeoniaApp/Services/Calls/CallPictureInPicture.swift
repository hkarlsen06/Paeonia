import AVKit
import SwiftUI
import UIKit

/// Keeps the partner's video going in system Picture in Picture when the app goes to the
/// background during a video call, or their shared screen while they share it. While their phone
/// has paused the camera, the camera's last frame shows blurred with a pause symbol. While the
/// partner shows no video and this phone's camera is on, the window shows the partner's photo, as
/// FaceTime does, because iOS lets an iPhone's camera run outside the app only while the app is
/// in Picture in Picture. Inside the app the floating bubble shows the call instead.
final class CallPictureInPicture {
    /// What the window shows.
    enum Content {
        case camera
        case screen
        /// The partner's photo with a camera-off symbol.
        case photo
    }

    private let contentController = AVPictureInPictureVideoCallViewController()
    private var controller: AVPictureInPictureController?
    /// The window's content. Showing another keeps the running Picture in Picture and its source,
    /// which a new source would end.
    private let cameraView: UIView
    private let screenView: UIView
    private let photo = UIHostingController(rootView: CallPictureInPicturePhoto(assetID: nil, name: ""))
    /// Over the camera while it is paused. A UIKit view, because the window's content is UIKit.
    private let pauseCover = CallPictureInPicture.makePauseCover()
    private var isCameraPaused = false
    private var shown = Content.camera
    /// The upright size of each one's latest frame.
    private var videoSizes: [CallVideoSource: CGSize] = [:]
    /// Every view showing the partner's video or screen, such as the call screen's and the bubble's.
    private var partnerViews: [WeakView] = []
    /// Every view behind the partner's photo, which Picture in Picture starts from while it shows
    /// the photo.
    private var photoAnchors: [WeakView] = []
    /// The partner's video the person sees, which the system animates into Picture in Picture.
    private weak var sourceView: UIView?
    private var isEnabled = false
    private var resignObserver: (any NSObjectProtocol)?
    private var activeObserver: (any NSObjectProtocol)?

    init(partner: CallVideoFeed, partnerScreen: CallVideoFeed) {
        cameraView = partner.makeView()
        screenView = partnerScreen.makeView()
        screenView.isHidden = true
        let photoView: UIView = photo.view
        photoView.backgroundColor = .clear
        photoView.isHidden = true
        contentController.addChild(photo)
        for video in [cameraView, screenView, pauseCover, photoView] {
            video.translatesAutoresizingMaskIntoConstraints = false
            contentController.view.addSubview(video)
            NSLayoutConstraint.activate([
                video.leadingAnchor.constraint(equalTo: contentController.view.leadingAnchor),
                video.trailingAnchor.constraint(equalTo: contentController.view.trailingAnchor),
                video.topAnchor.constraint(equalTo: contentController.view.topAnchor),
                video.bottomAnchor.constraint(equalTo: contentController.view.bottomAnchor),
            ])
        }
        photo.didMove(toParent: contentController)
        // The call screen and the bubble swap with animations that end after the last change
        // to window membership, so just before the app leaves, a source that has left the screen
        // is replaced.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(isLeaving: true) }
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

    private static func makePauseCover() -> UIVisualEffectView {
        let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        let pause = UIImageView(image: UIImage(
            systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
        pause.tintColor = .white
        pause.translatesAutoresizingMaskIntoConstraints = false
        cover.contentView.addSubview(pause)
        NSLayoutConstraint.activate([
            pause.centerXAnchor.constraint(equalTo: cover.contentView.centerXAnchor),
            pause.centerYAnchor.constraint(equalTo: cover.contentView.centerYAnchor),
        ])
        cover.isHidden = true
        return cover
    }

    /// The upright size of the partner's frames, which Picture in Picture's window takes while it
    /// shows them.
    func setVideoSize(_ size: CGSize, of source: CallVideoSource) {
        videoSizes[source] = size
        contentController.preferredContentSize = contentSize
    }

    func show(_ content: Content) {
        guard content != shown else { return }
        shown = content
        cameraView.isHidden = content != .camera
        screenView.isHidden = content != .screen
        photo.view.isHidden = content != .photo
        pauseCover.isHidden = !isCameraPaused || content != .camera
        contentController.preferredContentSize = contentSize
        update()
    }

    /// The shape of the video shown, or an upright phone's while the photo shows.
    private var contentSize: CGSize {
        switch shown {
        case .camera: videoSizes[.partner] ?? .zero
        case .screen: videoSizes[.partnerScreen] ?? .zero
        case .photo: CGSize(width: 720, height: 1_280)
        }
    }

    /// The partner's phone paused their camera, so its last frame shows blurred with a pause symbol
    /// while the camera is what the window shows.
    func setCameraPaused(_ paused: Bool) {
        isCameraPaused = paused
        pauseCover.isHidden = !paused || shown != .camera
    }

    /// A view behind the partner's photo on screen, with the photo it stands for.
    func trackPhoto(_ anchor: CallPictureInPictureAnchor, assetID: UUID?, name: String) {
        photo.rootView = CallPictureInPicturePhoto(assetID: assetID, name: name)
        photoAnchors.removeAll { $0.view == nil }
        photoAnchors.append(WeakView(view: anchor))
        anchor.onWindowChange = { [weak self] in self?.update() }
    }

    /// Picture in Picture may start during a call while the partner shows a video, or while this
    /// phone's camera is on. The engine calls this on every change to the call, which also chooses
    /// the source again.
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

    /// Points Picture in Picture at the partner's video the person sees, or at their photo while the
    /// window shows it. A view can stay in a window while another covers it, or while it fades or
    /// moves away, so being in a window is not enough.
    ///
    /// iOS starts Picture in Picture as the app leaves only from a controller made before, so
    /// `isLeaving` keeps the controller while its view is still on screen. A new one made then
    /// left the camera to stop outside the app (2026-11-17).
    private func update(isLeaving: Bool = false) {
        guard isEnabled, AVPictureInPictureController.isPictureInPictureSupported() else {
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
            return
        }
        // Changing the source of a running Picture in Picture would end it.
        guard controller?.isPictureInPictureActive != true else { return }
        partnerViews.removeAll { $0.view == nil }
        photoAnchors.removeAll { $0.view == nil }
        let candidates = shown == .photo ? photoAnchors : partnerViews
        if isLeaving, controller != nil, let sourceView, Self.isVisible(sourceView),
           candidates.contains(where: { $0.view === sourceView }) {
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            return
        }
        guard let visible = candidates.compactMap(\.view).filter(Self.isVisible).max(by: {
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

/// A clear view behind the partner's photo on the call screen and in the bubble, which Picture in
/// Picture grows out of while it shows the photo.
final class CallPictureInPictureAnchor: UIView {
    var onWindowChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }
}

/// The partner's photo and a camera-off symbol on the call screen's colors, for Picture in Picture
/// while the partner shows no video.
struct CallPictureInPicturePhoto: View {
    let assetID: UUID?
    let name: String

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.42
            VStack(spacing: size * 0.18) {
                PaeoniaProfilePhotoAvatar(mediaAssetID: assetID, name: name, tint: .paeoniaPartnerTwo, size: size)
                Image(systemName: "video.slash.fill")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            LinearGradient(
                colors: [
                    Color.paeoniaBackgroundPrimary.mix(with: .paeoniaPartnerTwo, by: 0.34),
                    Color.paeoniaBackgroundPrimary,
                    Color.paeoniaBackgroundPrimary.mix(with: .paeoniaPartnerOne, by: 0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}
