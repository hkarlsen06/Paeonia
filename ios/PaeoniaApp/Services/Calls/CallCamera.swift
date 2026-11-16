import AVFoundation
@preconcurrency import LiveKitWebRTC

/// The phone's camera for a video call. Frames go to the call's video source.
final class CallCamera {
    /// Sharp full screen on the partner's iPad. Through TURN, on a hot phone and on a weak
    /// connection, WebRTC sends it smaller (`CallVideoLimits`).
    private static let targetPixels = 1_920 * 1_080
    /// The partner shows the camera small beside a shared screen.
    private static let besideScreenPixels = 640 * 480
    /// Past this the picture is too soft to be worth sending.
    private static let maxZoom = 10.0

    /// True when iOS stops the running camera for now, such as when the app leaves the screen
    /// without Picture in Picture or another app takes the camera, and false when it sends again.
    var onInterruption: ((Bool) -> Void)?
    /// Captures about 640x480 instead of 1080p, in the same shape, so the viewfinder and the
    /// partner's picture keep theirs. A running camera takes a change at its next start.
    var isBesideScreen = false

    private let capturer: LKRTCCameraVideoCapturer
    private var isCapturing = false
    private var isInterrupted = false
    /// The running camera, so its frame rate can change without a restart.
    private var device: AVCaptureDevice?
    /// The back camera while it runs, so the call screen can zoom it.
    private var backCamera: AVCaptureDevice?
    private var startedBesideScreen = false
    /// Lowered while the phone is hot or beside a shared screen (`CallVideoLimits`).
    private var maxFramesPerSecond = 30
    private var observers: [any NSObjectProtocol] = []

    init(source: LKRTCVideoSource) {
        capturer = LKRTCCameraVideoCapturer(delegate: source)
        let session = capturer.captureSession
        // Keeps the camera sending while the partner's video plays in Picture in Picture.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
        observers = [
            (AVCaptureSession.wasInterruptedNotification, true),
            (AVCaptureSession.interruptionEndedNotification, false),
        ].map { name, isInterrupted in
            NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInterrupted(isInterrupted) }
            }
        }
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts the front or back camera, or switches to it. `onStarted` runs on the main thread
    /// once frames come from that camera, with the back camera's zoom, which starts at the main
    /// lens.
    ///
    /// A switch stops the running camera first. The capturer removes only inputs for the camera
    /// it is starting, so starting over a running one leaves the old connection on the shared
    /// multi-camera session, and adding the new one throws.
    func start(front: Bool, onStarted: @escaping @MainActor @Sendable (CallCameraZoom?) -> Void) {
        guard case let (device, format)? = Self.camera(front: front, besideScreen: isBesideScreen) else { return }
        stop()
        isCapturing = true
        self.device = device
        startedBesideScreen = isBesideScreen
        backCamera = front ? nil : device
        capturer.startCapture(
            with: device,
            format: format,
            fps: Self.frameRate(maxFramesPerSecond, in: format),
            completionHandler: { @Sendable [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        // After the capturer's start, which sets a zoom of its own.
                        onStarted(self?.zoomToMainLens())
                    }
                }
            }
        )
    }

    /// The running camera captures at the size it had before `isBesideScreen` changed. False
    /// while `stop()` reports the end of an interruption, because no camera runs then.
    var needsRestart: Bool {
        device != nil && startedBesideScreen != isBesideScreen
    }

    func stop() {
        backCamera = nil
        device = nil
        setInterrupted(false)
        guard isCapturing else { return }
        isCapturing = false
        capturer.stopCapture()
    }

    /// Caps the frame rate the camera captures at, now and for the next start.
    func setMaxFramesPerSecond(_ rate: Int) {
        guard rate != maxFramesPerSecond else { return }
        maxFramesPerSecond = rate
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(Self.frameRate(rate, in: device.activeFormat)))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    private func setInterrupted(_ interrupted: Bool) {
        guard interrupted != isInterrupted, !interrupted || isCapturing else { return }
        isInterrupted = interrupted
        onInterruption?(interrupted)
    }

    /// `rate`, kept inside what the camera's format can do, because a frame duration outside
    /// its range raises an exception.
    private static func frameRate(_ rate: Int, in format: AVCaptureDevice.Format) -> Int {
        let ranges = format.videoSupportedFrameRateRanges
        guard let lowest = ranges.map(\.minFrameRate).min(), let highest = ranges.map(\.maxFrameRate).max() else {
            return rate
        }
        return Int(min(max(Double(rate), lowest.rounded(.up)), highest))
    }

    /// Zooms the back camera to `factor`, kept inside its range. Returns the zoom it set, or nil
    /// when the back camera is not running or would not take it.
    func setZoom(_ factor: Double) -> Double? {
        guard let backCamera, let range = Self.zoomRange(of: backCamera) else { return nil }
        let applied = min(max(factor, range.lowerBound), range.upperBound)
        do {
            try backCamera.lockForConfiguration()
        } catch {
            return nil
        }
        // Kept inside the device's own range too, because one outside it throws.
        backCamera.videoZoomFactor = min(
            max(CGFloat(applied) / backCamera.displayVideoZoomFactorMultiplier, backCamera.minAvailableVideoZoomFactor),
            backCamera.maxAvailableVideoZoomFactor
        )
        backCamera.unlockForConfiguration()
        return applied
    }

    private func zoomToMainLens() -> CallCameraZoom? {
        guard let backCamera, let range = Self.zoomRange(of: backCamera), let factor = setZoom(1) else { return nil }
        return CallCameraZoom(range: range, factor: factor)
    }

    /// The front camera, or the back camera that joins the most lenses, so zooming out reaches the
    /// ultra wide. A camera with no format the capturer can use is skipped.
    ///
    /// Not `LKRTCCameraVideoCapturer.captureDevices()`, which lists only single wide lenses, so the
    /// back camera could not zoom below 1×.
    private static func camera(front: Bool, besideScreen: Bool) -> (AVCaptureDevice, AVCaptureDevice.Format)? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        let matching = devices.filter { $0.position == (front ? .front : .back) }
        let candidates = front
            ? Array(matching.prefix(1))
            : matching.sorted { $0.constituentDevices.count > $1.constituentDevices.count }
        for device in candidates.isEmpty ? Array(devices.prefix(1)) : candidates {
            if let format = format(for: device, besideScreen: besideScreen) {
                return (device, format)
            }
        }
        return nil
    }

    /// In the Camera app's units. Nil when the camera cannot zoom.
    private static func zoomRange(of device: AVCaptureDevice) -> ClosedRange<Double>? {
        let multiplier = device.displayVideoZoomFactorMultiplier
        let lower = Double(device.minAvailableVideoZoomFactor * multiplier)
        let upper = min(Double(device.maxAvailableVideoZoomFactor * multiplier), maxZoom)
        return lower < upper ? lower...upper : nil
    }

    /// The format nearest 1080p, or beside a shared screen the one nearest 640x480 in that
    /// format's shape.
    private static func format(for device: AVCaptureDevice, besideScreen: Bool) -> AVCaptureDevice.Format? {
        let formats = LKRTCCameraVideoCapturer.supportedFormats(for: device)
        let full = nearest(targetPixels, in: formats)
        guard besideScreen, let full else { return full }
        let shape = CMVideoFormatDescriptionGetDimensions(full.formatDescription)
        let sameShape = formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Int(size.width) * Int(shape.height) == Int(size.height) * Int(shape.width)
        }
        return nearest(besideScreenPixels, in: sameShape)
    }

    private static func nearest(_ target: Int, in formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        formats.min { lhs, rhs in
            abs(pixels(lhs) - target) < abs(pixels(rhs) - target)
        }
    }

    private static func pixels(_ format: AVCaptureDevice.Format) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(dimensions.width) * Int(dimensions.height)
    }
}
