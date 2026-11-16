import Foundation
@preconcurrency import LiveKitWebRTC

/// How a call compresses its audio and video. `scripts/call-media-probe` checks each choice
/// on two connections in one Mac process.
nonisolated enum CallCodecs {
    /// Prefers RED-wrapped Opus for audio and limits the video for TURN until the call knows its
    /// path. Call it for each transceiver before the offer or answer that first carries it.
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
            limitVideo(transceiver.sender, to: CallVideoLimits(path: .turn))
        default:
            break
        }
    }

    /// Sets the video's largest bitrate, picture size and frame rate. The camera captures 1080p.
    /// WebRTC can change them during a call without a new offer, and still goes lower on its own
    /// for the network estimate or a busy encoder (`qualityLimitationReason`), so these are
    /// ceilings that never fight its adaptation.
    static func limitVideo(_ sender: LKRTCRtpSender, to limits: CallVideoLimits) {
        let parameters = sender.parameters
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = NSNumber(value: limits.maxBitsPerSecond)
            encoding.scaleResolutionDownBy = NSNumber(value: limits.scaleDown)
            encoding.maxFramerate = NSNumber(value: limits.maxFramesPerSecond)
        }
        sender.parameters = parameters
    }

    /// The shared screen keeps its full size and sends fewer frames when bits run short, because
    /// a smaller picture blurs text.
    static func limitScreen(_ sender: LKRTCRtpSender, to limits: CallVideoLimits) {
        let parameters = sender.parameters
        parameters.degradationPreference = NSNumber(value: LKRTCDegradationPreference.maintainResolution.rawValue)
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

/// The most one video sender may send. The camera and the shared screen each have a table for
/// the path and one for the phone's heat, and take the lower of each. These tables are the only
/// place the limits live.
nonisolated struct CallVideoLimits: Equatable, Sendable {
    var maxBitsPerSecond: Int
    /// How much WebRTC shrinks the picture before it encodes it. The camera captures 1080p.
    var scaleDown: Double
    /// Also the camera's capture rate, because capturing costs heat too.
    var maxFramesPerSecond: Int

    /// The camera's limits. Beside a shared screen it keeps what the screen leaves.
    init(path: CallMediaPath, heat: CallHeat = .normal, besideScreen: Bool = false) {
        self = Self.limits(for: path).lowered(to: Self.limits(for: heat))
        if besideScreen {
            maxBitsPerSecond -= Self.screen(path: path, heat: heat).maxBitsPerSecond
        }
    }

    private init(_ maxBitsPerSecond: Int, _ scaleDown: Double, _ maxFramesPerSecond: Int) {
        self.maxBitsPerSecond = maxBitsPerSecond
        self.scaleDown = scaleDown
        self.maxFramesPerSecond = maxFramesPerSecond
    }

    /// The shared screen's limits.
    static func screen(path: CallMediaPath, heat: CallHeat = .normal) -> CallVideoLimits {
        screenLimits(for: path).lowered(to: screenLimits(for: heat))
    }

    private func lowered(to other: CallVideoLimits) -> CallVideoLimits {
        CallVideoLimits(
            min(maxBitsPerSecond, other.maxBitsPerSecond),
            max(scaleDown, other.scaleDown),
            min(maxFramesPerSecond, other.maxFramesPerSecond)
        )
    }

    /// A direct call sends 1080p at up to 4 Mbps, which looks sharp full screen on an iPad. H.265
    /// looks good on a phone at 720p and 1.5 Mbps, so TURN traffic stays there. The limit also
    /// replaces WebRTC's own, which would hold 1080p at 2.5 Mbps and 320x180 at 600 kbps.
    private static func limits(for path: CallMediaPath) -> CallVideoLimits {
        switch path {
        case .direct: CallVideoLimits(4_000_000, 1, 30)
        case .turn: CallVideoLimits(1_500_000, 1.5, 30)
        }
    }

    /// A warm phone sends 720p at 24 frames a second, a third of the pixels each second that 1080p
    /// at 30 takes, and a hot one 540p at 15, an eighth. Both still show a face well on a phone.
    private static func limits(for heat: CallHeat) -> CallVideoLimits {
        switch heat {
        case .normal: CallVideoLimits(4_000_000, 1, 30)
        case .warm: CallVideoLimits(1_500_000, 1.5, 24)
        case .hot: CallVideoLimits(600_000, 2, 15)
        }
    }

    /// The partner shows a shared screen large and the camera small, so the screen gets most of
    /// the camera's bits for the path and the heat, and the two together stay inside them and
    /// TURN's 1.5 Mbps. The screen keeps its full size, up to 1080p's pixel count, because a
    /// smaller picture blurs text. It sends at most 15 frames a second, which is enough for
    /// scrolling and moving between apps, and fewer as the phone heats up. ScreenCaptureKit
    /// sends up to 60 a second on iOS, where its frame interval cannot be set.
    private static func screenLimits(for path: CallMediaPath) -> CallVideoLimits {
        switch path {
        case .direct: CallVideoLimits(2_500_000, 1, 15)
        case .turn: CallVideoLimits(1_000_000, 1, 15)
        }
    }

    private static func screenLimits(for heat: CallHeat) -> CallVideoLimits {
        switch heat {
        case .normal: CallVideoLimits(2_500_000, 1, 15)
        case .warm: CallVideoLimits(1_000_000, 1, 10)
        case .hot: CallVideoLimits(400_000, 1, 5)
        }
    }
}

/// Offers H.265 first. Every iPhone that runs iOS 27 encodes it in hardware, and it needs fewer
/// bits than H.264 for the same picture. LiveKit's default factory leaves it out although the
/// build has the encoder.
nonisolated final class CallVideoEncoderFactory: NSObject, LKRTCVideoEncoderFactory {
    private let defaults = LKRTCDefaultVideoEncoderFactory()

    func createEncoder(_ info: LKRTCVideoCodecInfo) -> (any LKRTCVideoEncoder)? {
        info.name == kLKRTCVideoCodecH265Name ? LKRTCVideoEncoderH265(codecInfo: info) : defaults.createEncoder(info)
    }

    func supportedCodecs() -> [LKRTCVideoCodecInfo] {
        [LKRTCVideoCodecInfo(name: kLKRTCVideoCodecH265Name)] + defaults.supportedCodecs()
    }
}
