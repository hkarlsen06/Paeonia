import AVFoundation
@preconcurrency import LiveKitWebRTC

/// The phone's camera for a video call. Frames go to the call's video source.
final class CallCamera {
    /// Sharp full screen on the partner's iPad. Through TURN, and on a weak connection, WebRTC
    /// sends it smaller (`CallMediaPath`).
    private static let targetPixels = 1_920 * 1_080
    private static let maxFramesPerSecond = 30.0

    private let capturer: LKRTCCameraVideoCapturer

    init(source: LKRTCVideoSource) {
        capturer = LKRTCCameraVideoCapturer(delegate: source)
        let session = capturer.captureSession
        // Keeps the camera sending while the partner's video plays in Picture in Picture.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
    }

    /// Starts the front or back camera, or switches to it. `onStarted` runs on the main thread
    /// once frames come from that camera.
    func start(front: Bool, onStarted: @escaping @MainActor @Sendable () -> Void) {
        let position: AVCaptureDevice.Position = front ? .front : .back
        let devices = LKRTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == position }) ?? devices.first,
              let format = Self.format(for: device)
        else {
            return
        }
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Self.maxFramesPerSecond
        capturer.startCapture(
            with: device,
            format: format,
            fps: Int(min(maxRate, Self.maxFramesPerSecond)),
            completionHandler: { @Sendable _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { onStarted() } }
            }
        )
    }

    func stop() {
        capturer.stopCapture()
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
