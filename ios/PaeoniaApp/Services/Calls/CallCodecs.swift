import Foundation
@preconcurrency import LiveKitWebRTC

/// How a call compresses its audio and video. `scripts/call-media-probe` checks each choice
/// on two connections in one Mac process.
nonisolated enum CallCodecs {
    /// Prefers RED-wrapped Opus for audio and sets the video's limits. Call it for each
    /// transceiver before the offer or answer that first carries it.
    static func configure(_ transceiver: LKRTCRtpTransceiver, factory: LKRTCPeerConnectionFactory) {
        switch transceiver.mediaType {
        case .audio:
            // RED repeats the previous audio frame in each packet, so one lost packet loses no sound.
            let codecs = factory.rtpReceiverCapabilities(forKind: kLKRTCMediaStreamTrackKindAudio).codecs
            let first = ["red", "opus"]
            let preferred = first.flatMap { name in codecs.filter { $0.name.lowercased() == name } }
                + codecs.filter { !first.contains($0.name.lowercased()) }
            try? transceiver.setCodecPreferences(preferred, error: ())
        case .video:
            limitVideo(transceiver.sender, to: CallVideoLimits())
        default:
            break
        }
    }

    /// Sets the video's largest bitrate, picture size and frame rate. WebRTC can change them
    /// during a call without a new offer, and still goes lower on its own for the network
    /// estimate or a busy encoder (`qualityLimitationReason`), so these are ceilings that never
    /// fight its adaptation.
    static func limitVideo(_ sender: LKRTCRtpSender, to limits: CallVideoLimits) {
        let parameters = sender.parameters
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = NSNumber(value: limits.maxBitsPerSecond)
            encoding.scaleResolutionDownBy = NSNumber(value: limits.scaleDown)
            encoding.maxFramerate = NSNumber(value: limits.maxFramesPerSecond)
        }
        sender.parameters = parameters
    }

    /// The shared screen's video source. WebRTC's screen-sharing mode (`forScreenCast: true`)
    /// caps the H.265 and H.264 encoders' quantizer at 39 (`MaxAllowedFrameQP`), so VideoToolbox
    /// drops frames to stay under it, and turns off the quality scaler that lowers the picture
    /// size when the quantizer runs high. The share then plays like stop motion.
    static func screenSource(from factory: LKRTCPeerConnectionFactory) -> LKRTCVideoSource {
        factory.videoSource(forScreenCast: false)
    }

    /// The most `startVideoEstimate` lifts WebRTC's estimate to.
    static let videoStartBitsPerSecond = 2_500_000

    /// Lifts WebRTC's estimate of what this phone may send to `limits`, at most
    /// `videoStartBitsPerSecond`, just before a video starts sending. The estimate grows only with
    /// what the phone sends, so after voice alone it sits at WebRTC's 300 kbps start or lower. On
    /// 2026-11-17 an iPad's first shared frames backed up at that rate, WebRTC took the delay for a
    /// full network and cut the estimate to 125 kbps, and the screen went at 286x200 while the
    /// estimate climbed back for most of a minute. WebRTC also picks the picture's size from the
    /// estimate at the first frames and grows it a step every few seconds after, so the lift has
    /// to come first. With nothing sending, a lifted estimate falls back within about a second.
    /// WebRTC lowers it too when the network cannot carry it. `available` is the estimate now,
    /// which this never lowers.
    static func startVideoEstimate(_ connection: LKRTCPeerConnection, available: Double?, limits: CallVideoLimits) {
        let start = min(videoStartBitsPerSecond, limits.maxBitsPerSecond)
        guard (available ?? 0) < Double(start) else { return }
        connection.setBweMinBitrateBps(nil, currentBitrateBps: NSNumber(value: start), maxBitrateBps: nil)
    }

    /// The shared screen keeps its frame rate when bits or the encoder run short and sends a
    /// smaller picture instead, because softer text is easier to watch than a picture that jumps.
    /// It comes first in a share, so it gets sixteen times the camera's share of a network too
    /// slow for both, and the camera gives way.
    static func limitScreen(_ sender: LKRTCRtpSender, to limits: CallVideoLimits) {
        let parameters = sender.parameters
        parameters.degradationPreference = NSNumber(value: LKRTCDegradationPreference.maintainFramerate.rawValue)
        for encoding in parameters.encodings {
            encoding.bitratePriority = 16
        }
        sender.parameters = parameters
        limitVideo(sender, to: limits)
    }

    /// Asks the partner's phone to stop sending audio while this person is silent (Opus DTX).
    /// WebRTC has no setting for it, so it goes into the Opus line of the session description.
    static func withOpusDTX(_ description: LKRTCSessionDescription) -> LKRTCSessionDescription {
        LKRTCSessionDescription(type: description.type, sdp: addingOpusDTX(to: description.sdp))
    }

    /// Adds `usedtx=1` to each Opus `a=fmtp` line and leaves every other byte as it was.
    private static func addingOpusDTX(to sdp: String) -> String {
        let lines = sdp.components(separatedBy: "\r\n")
        let opusPayloadTypes = Set(lines.compactMap { line -> Substring? in
            guard let (payloadType, value) = attribute("a=rtpmap:", in: line),
                  value.lowercased().hasPrefix("opus/")
            else {
                return nil
            }
            return payloadType
        })
        return lines.map { line in
            guard let (payloadType, parameters) = attribute("a=fmtp:", in: line),
                  opusPayloadTypes.contains(payloadType),
                  !parameters.split(separator: ";").contains("usedtx=1")
            else {
                return line
            }
            return line + ";usedtx=1"
        }
        .joined(separator: "\r\n")
    }

    /// Splits `a=rtpmap:111 opus/48000/2` into `111` and `opus/48000/2`.
    private static func attribute(_ prefix: String, in line: String) -> (Substring, Substring)? {
        guard line.hasPrefix(prefix) else { return nil }
        let rest = line.dropFirst(prefix.count)
        guard let space = rest.firstIndex(of: " ") else { return nil }
        return (rest[..<space], rest[rest.index(after: space)...])
    }
}

/// How a call's media travels between the two phones.
nonisolated enum CallMediaPath: Equatable, Sendable {
    /// Straight between the phones, so only their own networks limit the video.
    case direct
    /// Through Cloudflare's TURN server, which Paeonia pays for by the gigabyte.
    case turn

    /// Either end of the connection in use on a TURN server sends everything through it.
    init(localCandidateType: String, remoteCandidateType: String?) {
        self = localCandidateType == "relay" || remoteCandidateType == "relay" ? .turn : .direct
    }
}

/// How hot the phone is, for the video it sends. iOS lowers FaceTime's frame rate at `serious`,
/// and Apple asks apps to stop using the camera at `critical` (WWDC19 session 422).
nonisolated enum CallHeat: Equatable, Sendable {
    case normal
    /// `serious`, or Low Power Mode, which asks apps to save energy.
    case warm
    /// `critical`. The call screen also offers to turn the camera off.
    case hot

    init(_ thermalState: ProcessInfo.ThermalState, isLowPowerMode: Bool) {
        switch thermalState {
        case .critical: self = .hot
        case .serious: self = .warm
        default: self = isLowPowerMode ? .warm : .normal
        }
    }
}

/// The most one video sender may send. The camera and the shared screen each have a table for the
/// phone's heat, the same on every path: TURN costs more than a direct path, and the call spends
/// it for the picture (2026-11-17). These tables are the only place the limits live.
nonisolated struct CallVideoLimits: Equatable, Sendable {
    var maxBitsPerSecond: Int
    /// How much WebRTC shrinks the picture before it encodes it. The camera captures 1080p, or
    /// about 640x480 beside a shared screen (`CallCamera`), and the screen about 1280x720's
    /// pixel count (`CallScreenCapture`).
    var scaleDown: Double
    /// Also the camera's capture rate, because capturing costs heat too, and the most frames a
    /// second the shared screen hands WebRTC.
    var maxFramesPerSecond: Int

    /// The camera's limits. Beside a shared screen it takes `besideScreen(for:)`'s, because the
    /// screen comes first in a share and the partner shows the camera small.
    init(heat: CallHeat = .normal, besideScreen: Bool = false) {
        self = besideScreen ? Self.besideScreen(for: heat) : Self.limits(for: heat)
    }

    private init(_ maxBitsPerSecond: Int, _ scaleDown: Double, _ maxFramesPerSecond: Int) {
        self.maxBitsPerSecond = maxBitsPerSecond
        self.scaleDown = scaleDown
        self.maxFramesPerSecond = maxFramesPerSecond
    }

    /// The camera sends 1080p at up to 4 Mbps, which looks sharp full screen on an iPad, and
    /// replaces WebRTC's own limit, which would hold 1080p at 2.5 Mbps and 320x180 at 600 kbps. A
    /// warm phone sends 720p at 24 frames a second, a third of the pixels each second that 1080p
    /// at 30 takes, and a hot one 540p at 15, an eighth. Both still show a face well on a phone.
    private static func limits(for heat: CallHeat) -> CallVideoLimits {
        switch heat {
        case .normal: CallVideoLimits(4_000_000, 1, 30)
        case .warm: CallVideoLimits(1_500_000, 1.5, 24)
        case .hot: CallVideoLimits(600_000, 2, 15)
        }
    }

    /// The camera beside a shared screen, which captures about 640x480 (`CallCamera`). It sends
    /// 15 frames a second, and a warm or hot phone lowers it before the screen: 10 frames a second
    /// and 400 kbps when warm, and half its size at 150 kbps when hot.
    private static func besideScreen(for heat: CallHeat) -> CallVideoLimits {
        switch heat {
        case .normal: CallVideoLimits(1_500_000, 1, 15)
        case .warm: CallVideoLimits(400_000, 1, 10)
        case .hot: CallVideoLimits(150_000, 2, 10)
        }
    }

    /// The shared screen comes first in a share. It sends up to 30 frames a second, so scrolling
    /// and moving between apps look smooth, at up to 4 Mbps, because at 2.5 Mbps an iPhone's busy
    /// screen dropped a third of its frames while 8.9 Mbps went unused. ScreenCaptureKit sends up
    /// to 60 a second on iOS, where its frame interval cannot be set. A warm phone keeps the
    /// screen whole at 30 frames a second and 2.5 Mbps, and a hot one sends two thirds of its
    /// size at 24, while the camera beside it gives way first.
    static func screen(heat: CallHeat = .normal) -> CallVideoLimits {
        switch heat {
        case .normal: CallVideoLimits(4_000_000, 1, 30)
        case .warm: CallVideoLimits(2_500_000, 1, 30)
        case .hot: CallVideoLimits(1_000_000, 1.5, 24)
        }
    }
}

/// Offers H.265 first. Every iPhone that runs iOS 27 encodes it in hardware, and it needs fewer
/// bits than H.264 for the same picture. LiveKit's default factory leaves it out although the
/// build has the encoder. Its encoder is `CallH265Encoder`, which caps a frame's size.
nonisolated final class CallVideoEncoderFactory: NSObject, LKRTCVideoEncoderFactory {
    private let defaults = LKRTCDefaultVideoEncoderFactory()
    /// The H.265 encoders this factory made, for `scripts/call-media-probe`.
    let h265Encoders = NSHashTable<CallH265Encoder>.weakObjects()

    func createEncoder(_ info: LKRTCVideoCodecInfo) -> (any LKRTCVideoEncoder)? {
        guard info.name == kLKRTCVideoCodecH265Name else { return defaults.createEncoder(info) }
        let encoder = CallH265Encoder(codecInfo: info)
        h265Encoders.add(encoder)
        return encoder
    }

    func supportedCodecs() -> [LKRTCVideoCodecInfo] {
        [LKRTCVideoCodecInfo(name: kLKRTCVideoCodecH265Name)] + defaults.supportedCodecs()
    }
}
