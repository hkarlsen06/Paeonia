import AVFoundation
@preconcurrency import LiveKitWebRTC

/// The phone's camera for a video call. Frames go to the call's video source.
final class CallCamera {
    /// Sharp full screen on the partner's iPad. Through TURN, and on a weak connection, WebRTC
    /// sends it smaller (`CallMediaPath`).
    private static let targetPixels = 1_920 * 1_080
    private static let maxFramesPerSecond = 30.0
    /// Past this the picture is too soft to be worth sending.
    private static let maxZoom = 10.0

    private let capturer: LKRTCCameraVideoCapturer
    private var isCapturing = false
    /// The back camera while it runs, so the call screen can zoom it.
    private var backCamera: AVCaptureDevice?

    init(source: LKRTCVideoSource) {
        capturer = LKRTCCameraVideoCapturer(delegate: source)
        let session = capturer.captureSession
        // Keeps the camera sending while the partner's video plays in Picture in Picture.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
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
        guard case let (device, format)? = Self.camera(front: front) else { return }
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Self.maxFramesPerSecond
        stop()
        isCapturing = true
        backCamera = front ? nil : device
        capturer.startCapture(
            with: device,
            format: format,
            fps: Int(min(maxRate, Self.maxFramesPerSecond)),
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

    func stop() {
        backCamera = nil
        guard isCapturing else { return }
        isCapturing = false
        capturer.stopCapture()
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
    private static func camera(front: Bool) -> (AVCaptureDevice, AVCaptureDevice.Format)? {
        let devices = LKRTCCameraVideoCapturer.captureDevices()
        let matching = devices.filter { $0.position == (front ? .front : .back) }
        let candidates = front
            ? Array(matching.prefix(1))
            : matching.sorted { $0.constituentDevices.count > $1.constituentDevices.count }
        for device in candidates.isEmpty ? Array(devices.prefix(1)) : candidates {
            if let format = format(for: device) {
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

    private static func format(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        LKRTCCameraVideoCapturer.supportedFormats(for: device).min { lhs, rhs in
            abs(pixels(lhs) - targetPixels) < abs(pixels(rhs) - targetPixels)
        }
    }

    private static func pixels(_ format: AVCaptureDevice.Format) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(dimensions.width) * Int(dimensions.height)
    }
}
