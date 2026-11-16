import Foundation
import OSLog
@preconcurrency import LiveKitWebRTC

/// Reads the call's media stats every 2 seconds while the phones are connected, and logs one line
/// about them every 10 seconds: codecs, bitrates, losses, round trip time and whether the media
/// goes direct or through TURN. Read it in Console with the `CallStats` category. Each sample also
/// goes to `onSample`, the first one as soon as the phones connect, so the call can notice a weak
/// connection within seconds (`CallConnectionHealth`).
final class CallStatsLog {
    private static let logger = Logger(subsystem: "no.paeonia.app", category: "CallStats")

    /// Logs one line about the call next to the samples, such as how long it took to connect.
    static func note(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }

    private let sampleInterval: Duration
    private let lineInterval: Duration
    private let write: (String) -> Void
    private var task: Task<Void, Never>?

    init(
        sampleInterval: Duration = .seconds(2),
        lineInterval: Duration = .seconds(10),
        write: @escaping (String) -> Void = { logger.notice("\($0, privacy: .public)") }
    ) {
        self.sampleInterval = sampleInterval
        self.lineInterval = lineInterval
        self.write = write
    }

    func start(_ peerConnection: LKRTCPeerConnection, onSample: @escaping (CallStatsSample) -> Void = { _ in }) {
        guard task == nil else { return }
        let lineSeconds = Double(lineInterval.components.seconds)
        task = Task { [sampleInterval, write] in
            var lastLine = await CallStatsSample.read(peerConnection)
            onSample(lastLine)
            while true {
                try? await Task.sleep(for: sampleInterval)
                guard !Task.isCancelled else { return }
                let current = await CallStatsSample.read(peerConnection)
                onSample(current)
                // Stats timestamps drift a little from the sleep, so a line goes out once most of
                // the interval has passed.
                if current.seconds - lastLine.seconds >= lineSeconds - 0.5 {
                    write(current.line(since: lastLine))
                    lastLine = current
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// The counters the log needs from one WebRTC statistics report. Counters only grow, so two
/// samples give the rates between them.
nonisolated struct CallStatsSample: Sendable {
    nonisolated struct Outbound: Sendable {
        var codec: String?
        var bytesSent = 0
        var packetsSent = 0
        /// The bitrate WebRTC asks the encoder for, which the network estimate and the cap limit.
        var targetBitsPerSecond: Double?
    }

    /// What this phone received of one kind of the partner's media since the call started.
    nonisolated struct Inbound: Sendable {
        var bytesReceived = 0
        var packetsReceived = 0
        /// Counted from the sequence numbers, so a resent packet that arrives twice can make it
        /// negative (RFC 3550, section 6.4.1).
        var packetsLost = 0

        /// The share of the packets the partner sent that never arrived, or nil before any did.
        var lossPercent: Double? {
            let lost = max(packetsLost, 0)
            guard lost + packetsReceived > 0 else { return nil }
            return Double(lost) / Double(lost + packetsReceived) * 100
        }

        mutating func add(_ other: Inbound) {
            bytesReceived += other.bytesReceived
            packetsReceived += other.packetsReceived
            packetsLost += other.packetsLost
        }
    }

    var seconds: Double
    var audio = Outbound()
    var video = Outbound()
    var frameWidth: Int?
    var frameHeight: Int?
    var framesPerSecond: Double?
    var qualityLimitation: String?
    /// Video packets the partner's phone asked for again, so they were lost on the way.
    var videoNacks = 0
    var videoBytesResent = 0
    /// How unevenly the video packets reach the partner's phone. WebRTC sends less when the
    /// delay grows, even when nothing is lost.
    var partnerJitterSeconds: Double?
    var audioReceived = Inbound()
    /// The partner's camera, and their shared screen while they share it.
    var videoReceived = Inbound()
    /// What the partner's phone reports it never got of what this phone sent, audio and video
    /// together, from their receiver reports. It lags `packetsSent` by up to a report interval.
    var packetsLostAtPartner = 0
    var roundTripSeconds: Double?
    var availableOutgoingBitsPerSecond: Double?
    /// `host`, `srflx`, `prflx` or `relay` for each end of the path in use. Never an address.
    var localCandidateType: String?
    /// A partner's candidate that answers before its description arrives starts as `prflx`.
    /// WebRTC corrects it once the description comes, so a later sample shows `relay`.
    var remoteCandidateType: String?

    var bytesReceived: Int {
        audioReceived.bytesReceived + videoReceived.bytesReceived
    }

    var packetsLost: Int {
        audioReceived.packetsLost + videoReceived.packetsLost
    }

    /// Nil until the phones have picked a path.
    var mediaPath: CallMediaPath? {
        localCandidateType.map { CallMediaPath(localCandidateType: $0, remoteCandidateType: remoteCandidateType) }
    }

    init(seconds: Double) {
        self.seconds = seconds
    }

    static func read(_ peerConnection: LKRTCPeerConnection) async -> CallStatsSample {
        await withCheckedContinuation { continuation in
            peerConnection.statistics { continuation.resume(returning: CallStatsSample($0)) }
        }
    }

    init(_ report: LKRTCStatisticsReport) {
        let stats = report.statistics
        seconds = report.timestamp_us / 1_000_000
        for stat in stats.values {
            switch stat.type {
            case "outbound-rtp":
                let sent = Outbound(
                    codec: stats[stat.string("codecId") ?? ""]?.string("mimeType"),
                    bytesSent: Int(stat.number("bytesSent") ?? 0),
                    packetsSent: Int(stat.number("packetsSent") ?? 0),
                    targetBitsPerSecond: stat.number("targetBitrate")
                )
                if stat.string("kind") == "video" {
                    video = sent
                    frameWidth = stat.number("frameWidth").map { Int($0) }
                    frameHeight = stat.number("frameHeight").map { Int($0) }
                    framesPerSecond = stat.number("framesPerSecond")
                    qualityLimitation = stat.string("qualityLimitationReason")
                    videoNacks = Int(stat.number("nackCount") ?? 0)
                    videoBytesResent = Int(stat.number("retransmittedBytesSent") ?? 0)
                } else {
                    audio = sent
                }
            case "remote-inbound-rtp":
                packetsLostAtPartner += Int(stat.number("packetsLost") ?? 0)
                partnerJitterSeconds = stat.string("kind") == "video" ? stat.number("jitter") : partnerJitterSeconds
            case "inbound-rtp":
                let kind: WritableKeyPath<Self, Inbound> =
                    stat.string("kind") == "video" ? \.videoReceived : \.audioReceived
                self[keyPath: kind].add(Inbound(stat))
            case "transport":
                guard let pair = stats[stat.string("selectedCandidatePairId") ?? ""] else { continue }
                roundTripSeconds = pair.number("currentRoundTripTime")
                availableOutgoingBitsPerSecond = pair.number("availableOutgoingBitrate")
                localCandidateType = stats[pair.string("localCandidateId") ?? ""]?.string("candidateType")
                remoteCandidateType = stats[pair.string("remoteCandidateId") ?? ""]?.string("candidateType")
            default:
                break
            }
        }
    }

    /// One log line with the rates since `previous`.
    func line(since previous: CallStatsSample) -> String {
        let elapsed = max(seconds - previous.seconds, 0.001)
        func kbps(_ bytes: Int, _ earlier: Int) -> Int {
            Int((Double(bytes - earlier) * 8 / elapsed / 1_000).rounded())
        }
        func show<Value>(_ value: Value?) -> String {
            value.map { "\($0)" } ?? "-"
        }
        let frame = frameWidth.flatMap { width in frameHeight.map { "\(width)x\($0)" } }
        return [
            "audio \(show(audio.codec)) \(kbps(audio.bytesSent, previous.audio.bytesSent)) kbps",
            "video \(show(video.codec)) \(kbps(video.bytesSent, previous.video.bytesSent)) kbps"
                + " (target \(show(video.targetBitsPerSecond.map { Int(($0 / 1_000).rounded()) })))"
                + " \(show(frame)) \(show(framesPerSecond.map { Int($0.rounded()) })) fps"
                + " limit \(show(qualityLimitation))"
                + ", resent \(kbps(videoBytesResent, previous.videoBytesResent)) kbps"
                + " (\(videoNacks - previous.videoNacks) asked)"
                + ", jitter at partner \(show(partnerJitterSeconds.map { Int(($0 * 1_000).rounded()) })) ms",
            "receive \(kbps(bytesReceived, previous.bytesReceived)) kbps",
            "lost \(packetsLost - previous.packetsLost)",
            "rtt \(show(roundTripSeconds.map { Int(($0 * 1_000).rounded()) })) ms",
            "available \(show(availableOutgoingBitsPerSecond.map { Int(($0 / 1_000).rounded()) })) kbps",
            "path \(show(localCandidateType))/\(show(remoteCandidateType))",
        ].joined(separator: ", ")
    }
}

private nonisolated extension CallStatsSample.Inbound {
    init(_ stat: LKRTCStatistics) {
        bytesReceived = Int(stat.number("bytesReceived") ?? 0)
        packetsReceived = Int(stat.number("packetsReceived") ?? 0)
        packetsLost = Int(stat.number("packetsLost") ?? 0)
    }
}

private nonisolated extension LKRTCStatistics {
    func number(_ key: String) -> Double? {
        (values[key] as? NSNumber)?.doubleValue
    }

    func string(_ key: String) -> String? {
        values[key] as? String
    }
}
