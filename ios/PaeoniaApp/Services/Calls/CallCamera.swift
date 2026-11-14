import AVFoundation
@preconcurrency import WebRTC

/// The phone's camera for a video call. Frames go to the call's video source.
final class CallCamera {
    /// Big enough for a full screen on the partner's phone, small enough for a weak connection.
    private static let targetPixels = 1_280 * 720
    private static let maxFramesPerSecond = 30.0

    private let capturer: RTCCameraVideoCapturer

    init(source: RTCVideoSource) {
        capturer = RTCCameraVideoCapturer(delegate: source)
        let session = capturer.captureSession
        // Keeps the camera sending while the partner's video plays in Picture in Picture.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
    }

    func start(front: Bool) {
        let position: AVCaptureDevice.Position = front ? .front : .back
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == position }) ?? devices.first,
              let format = Self.format(for: device)
        else {
            return
        }
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Self.maxFramesPerSecond
        capturer.startCapture(with: device, format: format, fps: Int(min(maxRate, Self.maxFramesPerSecond)))
    }

    func stop() {
        capturer.stopCapture()
    }

    private static func format(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        RTCCameraVideoCapturer.supportedFormats(for: device).min { lhs, rhs in
            abs(pixels(lhs) - targetPixels) < abs(pixels(rhs) - targetPixels)
        }
    }

    private static func pixels(_ format: AVCaptureDevice.Format) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(dimensions.width) * Int(dimensions.height)
    }
}
