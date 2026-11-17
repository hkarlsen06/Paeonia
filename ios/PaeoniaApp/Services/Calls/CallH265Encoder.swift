import ObjectiveC
import VideoToolbox
@preconcurrency import LiveKitWebRTC

/// LiveKit's H.265 encoder with a cap on one frame's size (`DataRateLimits`), which it leaves out.
///
/// LiveKit hands VideoToolbox each frame with no duration and only an average bitrate, so
/// VideoToolbox gives a frame the bits of the time since the frame before. WebRTC drops frames
/// before the encoder when the encoder overshoots, because it trusts no Objective-C encoder's
/// rate control, and each drop made the next frame bigger. On 2026-11-17 an iPhone's shared
/// screen fell to 5 frames a second of about 125 KB each that way, while 24 a second went in.
/// With the cap a frame may take at most `framesInOne` frames' worth of bits, and a scene change
/// costs detail for a moment instead of the frames after it. VideoToolbox's `ExpectedFrameRate`
/// is left alone: set to the rate WebRTC measured, it dropped the frames that came faster, and a
/// hot phone's screen in `scripts/call-media-probe` fell from 23 frames a second to 16.
///
/// LiveKit keeps the session in `_compressionSession` and makes a new one when the picture's
/// size changes, so each frame checks whether the session is new. If a later build renames
/// the field, the encoder runs as LiveKit's does.
nonisolated final class CallH265Encoder: LKRTCVideoEncoderH265 {
    /// How many frames' worth of bits one frame may take.
    static let framesInOne = 4.0

    private static let sessionOffset = class_getInstanceVariable(LKRTCVideoEncoderH265.self, "_compressionSession")
        .map(ivar_getOffset)

    // Only touched on WebRTC's encoder queue.
    private var bitsPerSecond = 0
    private var framesPerSecond = 30
    private var limitedSession: VTCompressionSession?

    override func setBitrate(_ bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        let result = super.setBitrate(bitrateKbit, framerate: framerate)
        bitsPerSecond = Int(bitrateKbit) * 1_000
        framesPerSecond = max(Int(framerate), 1)
        limitedSession = nil
        applyLimits()
        return result
    }

    override func encode(
        _ frame: LKRTCVideoFrame,
        codecSpecificInfo info: (any LKRTCCodecSpecificInfo)?,
        frameTypes: [NSNumber]
    ) -> Int {
        applyLimits()
        return super.encode(frame, codecSpecificInfo: info, frameTypes: frameTypes)
    }

    /// The data rate limits VideoToolbox holds the running session to, as bytes and seconds by
    /// turns, or nil before there is a session, for `scripts/call-media-probe`.
    var appliedLimits: [Double]?? {
        guard let session else { return nil }
        var limits: CFTypeRef?
        _ = withUnsafeMutablePointer(to: &limits) {
            VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, allocator: nil, valueOut: $0)
        }
        return .some((limits as? [NSNumber])?.map(\.doubleValue))
    }

    private var session: VTCompressionSession? {
        guard let offset = Self.sessionOffset else { return nil }
        return UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
            .advanced(by: offset)
            .load(as: VTCompressionSession?.self)
    }

    private func applyLimits() {
        guard bitsPerSecond > 0, let session, session !== limitedSession else { return }
        limitedSession = session
        let bytesPerSecond = Double(bitsPerSecond) / 8
        let frameSeconds = 1 / Double(framesPerSecond)
        // One frame's time may hold `framesInOne` frames' worth, and a second at most 1.5 seconds'.
        let limits = [bytesPerSecond * frameSeconds * Self.framesInOne, frameSeconds, bytesPerSecond * 1.5, 1]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits as CFArray)
    }
}
