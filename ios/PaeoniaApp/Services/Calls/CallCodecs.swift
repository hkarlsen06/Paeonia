import Foundation
@preconcurrency import LiveKitWebRTC

/// How a call compresses its audio and video. `scripts/call-media-probe` checks each choice
/// on two connections in one Mac process.
nonisolated enum CallCodecs {
    /// WebRTC lets 720p video reach 2.5 Mbps. H.265 looks good on a phone screen at 1.5 Mbps, and
    /// the extra bits cost mobile data and TURN traffic. The cap also replaces WebRTC's lower
    /// limits for smaller pictures, such as 600 kbps at 320x180.
    static let maxVideoBitsPerSecond = 1_500_000

    /// Prefers RED-wrapped Opus for audio and caps the video bitrate. Call it for each
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
            let parameters = transceiver.sender.parameters
            for encoding in parameters.encodings {
                encoding.maxBitrateBps = NSNumber(value: maxVideoBitsPerSecond)
            }
            transceiver.sender.parameters = parameters
        default:
            break
        }
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
