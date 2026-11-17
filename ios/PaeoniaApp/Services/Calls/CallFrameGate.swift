@preconcurrency import CoreMedia
@preconcurrency import LiveKitWebRTC

/// Hands WebRTC the newest of a shared screen's frames, at most `setMaxFramesPerSecond` a second.
/// ScreenCaptureKit sends up to 60 a second on iOS, at uneven times, and WebRTC would only drop the
/// extra ones after it took them in, so they stop here. A screen that stands still sends no
/// frames, and the encoder can only repair a lost frame with a new one, so while sharing the last
/// frame goes again every second until the screen changes. Everything runs on `queue`.
nonisolated final class CallFrameGate: @unchecked Sendable {
    let queue: DispatchQueue
    private let source: LKRTCVideoSource
    private let capturer: LKRTCVideoCapturer
    /// The rest is only touched on `queue`.
    private var newest: (buffer: any LKRTCVideoFrameBuffer, rotation: LKRTCVideoRotation)?
    private var lastSent = ContinuousClock.now
    private var resendTimer: DispatchSourceTimer?
    private var minFrameGap = Duration.seconds(1) / 30
    /// A frame came sooner than `minFrameGap` after the last one sent, and the newest frame goes
    /// once the gap has passed.
    private var isSendWaiting = false

    init(source: LKRTCVideoSource, queue: DispatchQueue) {
        self.source = source
        self.queue = queue
        capturer = LKRTCVideoCapturer(delegate: source)
    }

    /// A new picture of the screen. Call on `queue`.
    func take(_ buffer: any LKRTCVideoFrameBuffer, rotation: LKRTCVideoRotation) {
        newest = (buffer, rotation)
        sendNewest()
    }

    func setMaxFramesPerSecond(_ rate: Int) {
        queue.async { [self] in minFrameGap = .seconds(1) / rate }
    }

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
            newest = nil
        }
    }

    /// Sends the newest frame now, or when `minFrameGap` has passed since the last send, so the
    /// last frame of a scroll still goes when no frame follows it.
    private func sendNewest() {
        guard !isSendWaiting else { return }
        let wait = minFrameGap - (ContinuousClock.now - lastSent)
        guard wait > .zero else { return send() }
        isSendWaiting = true
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(wait / .nanoseconds(1)))) { [self] in
            isSendWaiting = false
            sendNewest()
        }
    }

    private func resendIfStill() {
        guard ContinuousClock.now - lastSent >= .seconds(1) else { return }
        send()
    }

    private func send() {
        guard let newest else { return }
        lastSent = .now
        // Stamped as it goes, so the frames' times are as far apart as WebRTC gets them. WebRTC
        // limits the frame rate by these times, and the time a frame came would put a frame that
        // waited for the gap closer to the one before it.
        source.capturer(capturer, didCapture: LKRTCVideoFrame(
            buffer: newest.buffer, rotation: newest.rotation, timeStampNs: Self.now()))
    }

    private static func now() -> Int64 {
        Int64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1_000_000_000)
    }
}
