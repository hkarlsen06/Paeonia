@preconcurrency import LiveKitWebRTC

#if canImport(ScreenCaptureKit)
import CoreMedia
import ImageIO
import ScreenCaptureKit
import Synchronization

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

    /// What ScreenCaptureKit has handed this app's shares so far, for the call's stats. One picker
    /// serves the whole app, so one share runs at a time.
    static var captured: CallStatsSample.Captured {
        CallScreenFrames.captured
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

    /// The most frames a second WebRTC gets of the screen (`CallVideoLimits`).
    func setMaxFramesPerSecond(_ rate: Int) {
        frames.setMaxFramesPerSecond(rate)
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

    /// The screen's own shape, with at most as many pixels as 1280x720, which is 652 by 1412 on a
    /// phone whose screen is 1179 by 2556. That is under half of 1080p's pixels, so the encoder
    /// has room for 30 frames a second, and text stays readable on the partner's phone. iOS
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

    private static let maxPixels: CGFloat = 1_280 * 720

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
    /// Atomic so the stats can read them on the main thread without making `queue` wait.
    private static let picturesCaptured = Atomic(0)
    private static let pixelFormat = Atomic<OSType>(0)
    private var minFrameGap = Duration.seconds(1) / 30
    /// A frame came sooner than `minFrameGap` after the last one sent, and the newest frame goes
    /// once the gap has passed.
    private var isSendWaiting = false

    init(source: LKRTCVideoSource) {
        self.source = source
        capturer = LKRTCVideoCapturer(delegate: source)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let frame = Self.frame(from: sampleBuffer) else { return }
        Self.picturesCaptured.add(1, ordering: .relaxed)
        if Self.pixelFormat.load(ordering: .relaxed) == 0, let buffer = sampleBuffer.imageBuffer {
            Self.pixelFormat.store(CVPixelBufferGetPixelFormatType(buffer), ordering: .relaxed)
        }
        lastFrame = frame
        sendNewest()
    }

    /// iOS sends up to 60 frames a second, and WebRTC would only drop the extra ones after it
    /// took them in, so they stop here.
    func setMaxFramesPerSecond(_ rate: Int) {
        queue.async { [self] in minFrameGap = .seconds(1) / rate }
    }

    /// Sends the newest frame now, or when `minFrameGap` has passed since the last send, so the
    /// last frame of a scroll still goes when no frame follows it.
    private func sendNewest() {
        guard !isSendWaiting, let lastFrame else { return }
        let wait = minFrameGap - (ContinuousClock.now - lastSent)
        guard wait > .zero else { return send(lastFrame) }
        isSendWaiting = true
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(wait / .nanoseconds(1)))) { [self] in
            isSendWaiting = false
            sendNewest()
        }
    }

    static var captured: CallStatsSample.Captured {
        let format = pixelFormat.load(ordering: .relaxed)
        return CallStatsSample.Captured(
            frames: picturesCaptured.load(ordering: .relaxed),
            pixelFormat: format == 0 ? nil : Self.fourCharacters(format)
        )
    }

    /// `420f` for full-range 4:2:0, `BGRA` for 32-bit color. A code with an unprintable byte
    /// shows in hexadecimal.
    private static func fourCharacters(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }), let text = String(bytes: bytes, encoding: .ascii)
        else {
            return String(code, radix: 16)
        }
        return text
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

    static let captured = CallStatsSample.Captured()

    init(source _: LKRTCVideoSource) {}

    func setMaxFramesPerSecond(_: Int) {}

    func start() {}

    func stop() {}
}
#endif
