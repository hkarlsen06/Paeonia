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
            limitVideo(transceiver.sender, on: .turn)
        default:
            break
        }
    }

    /// Sets the video's largest bitrate and picture size for the path. The camera captures 1080p.
    /// WebRTC can change both during a call without a new offer.
    static func limitVideo(_ sender: LKRTCRtpSender, on path: CallMediaPath) {
        let parameters = sender.parameters
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = NSNumber(value: path.maxVideoBitsPerSecond)
            encoding.scaleResolutionDownBy = NSNumber(value: path.videoScaleDown)
        }
        sender.parameters = parameters
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

    /// A direct call sends 1080p at up to 4 Mbps, which looks sharp full screen on an iPad. H.265
    /// looks good on a phone at 720p and 1.5 Mbps, so TURN traffic stays there. The limit also
    /// replaces WebRTC's own, which would hold 1080p at 2.5 Mbps and 320x180 at 600 kbps.
    var maxVideoBitsPerSecond: Int {
        switch self {
        case .direct: 4_000_000
        case .turn: 1_500_000
        }
    }

    /// How much WebRTC shrinks the camera's 1080p picture before it encodes it.
    var videoScaleDown: Double {
        switch self {
        case .direct: 1
        case .turn: 1.5
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
