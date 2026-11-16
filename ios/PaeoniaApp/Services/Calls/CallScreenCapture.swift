@preconcurrency import LiveKitWebRTC

#if canImport(ScreenCaptureKit)
import CoreMedia
import ImageIO
import ScreenCaptureKit

/// This phone's whole screen, other apps included, while the person shares it during a call.
/// ScreenCaptureKit captures it inside the app and the frames go to the call's screen video source.
///
/// Only the system's picker can start a share, so `start()` shows it and sharing begins once the
/// person chooses there. The stream keeps running while Paeonia is in the background because the
/// app declares the `screen-capture` background mode.
final class CallScreenCapture {
    /// True once the stream runs, false when it stops, whether the app or the person stopped it.
    var onSharingChange: ((Bool) -> Void)?

    private enum Phase {
        case idle
        /// The system's picker is up. It can close without telling the app, so a new `start()`
        /// shows it again.
        case picking
        case starting(SCStream)
        case sharing(SCStream)
    }

    private var phase = Phase.idle
    private let frames: CallScreenFrames

    init(source: LKRTCVideoSource) {
        frames = CallScreenFrames(source: source)
        frames.capture = self
    }

    func start() {
        let picker = SCContentSharingPicker.shared
        switch phase {
        case .starting, .sharing:
            return
        case .idle:
            guard picker.isAvailable else { return }
            // One picker serves the whole app, and while it is active system UI can hand the app
            // a share too, so it is active only while it is up.
            picker.add(frames)
            picker.isActive = true
            phase = .picking
        case .picking:
            break
        }
        picker.present()
    }

    func stop() {
        let previous = phase
        phase = .idle
        releasePicker()
        frames.stopResending()
        switch previous {
        case .idle, .picking:
            break
        case let .starting(stream):
            stream.stopCapture(completionHandler: nil)
        case let .sharing(stream):
            stream.stopCapture(completionHandler: nil)
            onSharingChange?(false)
        }
    }

    fileprivate func picked(_ filter: SCContentFilter) {
        guard case .picking = phase else { return }
        releasePicker()
        let stream = SCStream(filter: filter, configuration: Self.configuration(for: filter), delegate: frames)
        do {
            try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: frames.queue)
        } catch {
            phase = .idle
            return
        }
        phase = .starting(stream)
        Task {
            do {
                try await stream.startCapture()
            } catch {
                if case let .starting(current) = phase, current === stream {
                    phase = .idle
                }
                return
            }
            guard case let .starting(current) = phase, current === stream else {
                // Stopped while it started, and a stop before the start ends can be lost.
                try? await stream.stopCapture()
                return
            }
            phase = .sharing(stream)
            frames.startResending()
            onSharingChange?(true)
        }
    }

    fileprivate func pickerClosed() {
        guard case .picking = phase else { return }
        phase = .idle
        releasePicker()
    }

    /// The system stopped the stream, such as when the person ended the share from its indicator.
    fileprivate func streamStopped(_ stream: SCStream) {
        switch phase {
        case let .starting(current) where current === stream, let .sharing(current) where current === stream:
            stop()
        default:
            break
        }
    }

    private func releasePicker() {
        let picker = SCContentSharingPicker.shared
        picker.isActive = false
        picker.remove(frames)
    }

    /// The screen's own shape, with at most as many pixels as the camera's 1080p, so the encoder
    /// works no harder than for the camera and text stays sharp on the partner's phone. iOS
    /// captures at the screen's full size otherwise, which is 3.8 million pixels on a large iPhone.
    private static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let width = filter.contentRect.width * CGFloat(filter.pointPixelScale)
        let height = filter.contentRect.height * CGFloat(filter.pointPixelScale)
        guard width > 0, height > 0 else { return configuration }
        let scale = min(1, (maxPixels / (width * height)).squareRoot())
        configuration.width = evenPixels(width * scale)
        configuration.height = evenPixels(height * scale)
        return configuration
    }

    private static let maxPixels: CGFloat = 1_920 * 1_080

    /// Video encoders take only even sizes.
    private static func evenPixels(_ value: CGFloat) -> Int {
        Int(value / 2) * 2
    }
}

/// ScreenCaptureKit's callbacks, which arrive on its own threads. Frames go straight to WebRTC on
/// `queue`, and the rest moves to the main thread.
private nonisolated final class CallScreenFrames: NSObject, SCStreamOutput, SCStreamDelegate,
    SCContentSharingPickerObserver, @unchecked Sendable {
    let queue = DispatchQueue(label: "no.paeonia.call-screen", qos: .userInteractive)
    /// Set and read on the main thread only.
    nonisolated(unsafe) weak var capture: CallScreenCapture?

    private let source: LKRTCVideoSource
    private let capturer: LKRTCVideoCapturer
    /// The rest is only touched on `queue`.
    private var lastFrame: LKRTCVideoFrame?
    private var lastSent = ContinuousClock.now
    private var resendTimer: DispatchSourceTimer?

    init(source: LKRTCVideoSource) {
        self.source = source
        capturer = LKRTCVideoCapturer(delegate: source)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let frame = Self.frame(from: sampleBuffer) else { return }
        lastFrame = frame
        send(frame)
    }

    /// A screen that stands still sends no frames, and the encoder can only repair a lost frame
    /// with a new one, so the last frame goes again every second until the screen changes.
    func startResending() {
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.resendIfStill() }
            timer.resume()
            resendTimer?.cancel()
            resendTimer = timer
        }
    }

    func stopResending() {
        queue.async { [self] in
            resendTimer?.cancel()
            resendTimer = nil
            lastFrame = nil
        }
    }

    private func resendIfStill() {
        guard let lastFrame, ContinuousClock.now - lastSent >= .seconds(1) else { return }
        send(LKRTCVideoFrame(buffer: lastFrame.buffer, rotation: lastFrame.rotation, timeStampNs: Self.now()))
    }

    private func send(_ frame: LKRTCVideoFrame) {
        lastSent = .now
        source.capturer(capturer, didCapture: frame)
    }

    /// A new picture, turned the way the person holds the phone. Frames that only say the screen
    /// did not change carry no picture.
    private static func frame(from sampleBuffer: CMSampleBuffer) -> LKRTCVideoFrame? {
        guard let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]])?.first,
            let status = (attachments[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)),
            status == .complete || status == .started,
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return nil
        }
        let orientation = (attachments[.videoOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init)
        return LKRTCVideoFrame(
            buffer: LKRTCCVPixelBuffer(pixelBuffer: pixelBuffer),
            rotation: rotation(for: orientation ?? .up),
            timeStampNs: now()
        )
    }

    /// The turns LiveKit applies to ReplayKit's frames, which carry the same orientation values.
    private static func rotation(for orientation: CGImagePropertyOrientation) -> LKRTCVideoRotation {
        switch orientation {
        case .left: ._90
        case .down: ._180
        case .right: ._270
        default: ._0
        }
    }

    private static func now() -> Int64 {
        Int64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1_000_000_000)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        nonisolated(unsafe) let stream = stream
        onMain { $0.streamStopped(stream) }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        nonisolated(unsafe) let filter = filter
        onMain { $0.picked(filter) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        onMain { $0.pickerClosed() }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        onMain { $0.pickerClosed() }
    }

    private func onMain(_ body: @escaping @MainActor (CallScreenCapture) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let capture = self.capture {
                    body(capture)
                }
            }
        }
    }
}
#else
/// The simulator's SDK has no ScreenCaptureKit, so a share never starts there.
final class CallScreenCapture {
    var onSharingChange: ((Bool) -> Void)?

    init(source _: LKRTCVideoSource) {}

    func start() {}

    func stop() {}
}
#endif
