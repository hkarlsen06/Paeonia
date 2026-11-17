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
    /// `starting` once the person picked, `on` once the stream runs, `failed` when the picker or
    /// the stream could not start, and `off` when a share stops, whether the app or the person
    /// stopped it.
    var onShareChange: ((CallScreenShare) -> Void)?

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
            guard picker.isAvailable else {
                onShareChange?(.failed)
                return
            }
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
        frames.gate.stopResending()
        CallScreenAudio.shared.stop()
        switch previous {
        case .idle, .picking:
            break
        case let .starting(stream), let .sharing(stream):
            stream.stopCapture(completionHandler: nil)
            onShareChange?(.off)
        }
    }

    /// The most frames a second WebRTC gets of the screen (`CallVideoLimits`).
    func setMaxFramesPerSecond(_ rate: Int) {
        frames.gate.setMaxFramesPerSecond(rate)
    }

    fileprivate func picked(_ filter: SCContentFilter) {
        guard case .picking = phase else { return }
        releasePicker()
        let stream = SCStream(filter: filter, configuration: Self.configuration(for: filter), delegate: frames)
        do {
            try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: frames.gate.queue)
            try stream.addStreamOutput(frames, type: .audio, sampleHandlerQueue: frames.audioQueue)
        } catch {
            phase = .idle
            onShareChange?(.failed)
            return
        }
        phase = .starting(stream)
        onShareChange?(.starting)
        Task {
            do {
                try await stream.startCapture()
            } catch {
                if case let .starting(current) = phase, current === stream {
                    phase = .idle
                    onShareChange?(.failed)
                }
                return
            }
            guard case let .starting(current) = phase, current === stream else {
                // Stopped while it started, and a stop before the start ends can be lost.
                try? await stream.stopCapture()
                return
            }
            phase = .sharing(stream)
            frames.gate.startResending()
            onShareChange?(.on)
        }
    }

    /// The person closed the picker without picking, or it could not show (`failed`).
    fileprivate func pickerClosed(failed: Bool) {
        guard case .picking = phase else { return }
        phase = .idle
        releasePicker()
        if failed { onShareChange?(.failed) }
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
        // The shared apps' sound, without Paeonia's, which plays the partner's voice.
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = CallScreenAudio.sampleRate
        configuration.channelCount = CallScreenAudio.channelCount
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

/// ScreenCaptureKit's callbacks, which arrive on its own threads. Frames go to WebRTC through
/// `gate` on `queue`, and the rest moves to the main thread.
private nonisolated final class CallScreenFrames: NSObject, SCStreamOutput, SCStreamDelegate,
    SCContentSharingPickerObserver, @unchecked Sendable {
    let gate: CallFrameGate
    /// The shared apps' sound, which goes to `CallScreenAudio`.
    let audioQueue = DispatchQueue(label: "no.paeonia.call-screen-audio", qos: .userInteractive)
    /// Set and read on the main thread only.
    nonisolated(unsafe) weak var capture: CallScreenCapture?

    /// Atomic so the stats can read them on the main thread without making the gate's queue wait.
    private static let picturesCaptured = Atomic(0)
    private static let pixelFormat = Atomic<OSType>(0)

    init(source: LKRTCVideoSource) {
        gate = CallFrameGate(
            source: source, queue: DispatchQueue(label: "no.paeonia.call-screen", qos: .userInteractive))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            return CallScreenAudio.shared.play(sampleBuffer)
        }
        guard type == .screen, let (buffer, rotation) = Self.picture(from: sampleBuffer) else { return }
        Self.picturesCaptured.add(1, ordering: .relaxed)
        if Self.pixelFormat.load(ordering: .relaxed) == 0 {
            Self.pixelFormat.store(CVPixelBufferGetPixelFormatType(buffer.pixelBuffer), ordering: .relaxed)
        }
        gate.take(buffer, rotation: rotation)
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

    /// A new picture, turned the way the person holds the phone. Frames that only say the screen
    /// did not change carry no picture.
    private static func picture(from sampleBuffer: CMSampleBuffer) -> (LKRTCCVPixelBuffer, LKRTCVideoRotation)? {
        guard let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]])?.first,
            let status = (attachments[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)),
            status == .complete || status == .started,
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return nil
        }
        let orientation = (attachments[.videoOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init)
        return (LKRTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation(for: orientation ?? .up))
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
        onMain { $0.pickerClosed(failed: false) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        onMain { $0.pickerClosed(failed: true) }
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
    var onShareChange: ((CallScreenShare) -> Void)?

    static let captured = CallStatsSample.Captured()

    init(source _: LKRTCVideoSource) {}

    func setMaxFramesPerSecond(_: Int) {}

    func start() {
        onShareChange?(.failed)
    }

    func stop() {}
}
#endif
