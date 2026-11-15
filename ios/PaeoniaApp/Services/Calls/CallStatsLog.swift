import Foundation
import OSLog
@preconcurrency import LiveKitWebRTC

/// Logs one line about the call's media every 10 seconds while the phones are connected:
/// codecs, bitrates, losses, round trip time and whether the media goes direct or through TURN.
/// Read it in Console with the `CallStats` category.
final class CallStatsLog {
    private static let logger = Logger(subsystem: "no.paeonia.app", category: "CallStats")

    private let interval: Duration
    private let write: (String) -> Void
    private var task: Task<Void, Never>?

    init(
        interval: Duration = .seconds(10),
        write: @escaping (String) -> Void = { logger.notice("\($0, privacy: .public)") }
    ) {
        self.interval = interval
        self.write = write
    }

    func start(_ peerConnection: LKRTCPeerConnection) {
        guard task == nil else { return }
        task = Task { [interval, write] in
            var previous = await CallStatsSample.read(peerConnection)
            while true {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let current = await CallStatsSample.read(peerConnection)
                write(current.line(since: previous))
                previous = current
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

    var seconds: Double
    var audio = Outbound()
    var video = Outbound()
    var frameWidth: Int?
    var frameHeight: Int?
    var framesPerSecond: Double?
    var qualityLimitation: String?
    var bytesReceived = 0
    var packetsLost = 0
    var roundTripSeconds: Double?
    var availableOutgoingBitsPerSecond: Double?
    /// `host`, `srflx`, `prflx` or `relay` for this phone's end of the path in use. Never an address.
    var localCandidateType: String?

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
                } else {
                    audio = sent
                }
            case "inbound-rtp":
                bytesReceived += Int(stat.number("bytesReceived") ?? 0)
                packetsLost += Int(stat.number("packetsLost") ?? 0)
            case "transport":
                guard let pair = stats[stat.string("selectedCandidatePairId") ?? ""] else { continue }
                roundTripSeconds = pair.number("currentRoundTripTime")
                availableOutgoingBitsPerSecond = pair.number("availableOutgoingBitrate")
                localCandidateType = stats[pair.string("localCandidateId") ?? ""]?.string("candidateType")
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
                + " limit \(show(qualityLimitation))",
            "receive \(kbps(bytesReceived, previous.bytesReceived)) kbps",
            "lost \(packetsLost - previous.packetsLost)",
            "rtt \(show(roundTripSeconds.map { Int(($0 * 1_000).rounded()) })) ms",
            "available \(show(availableOutgoingBitsPerSecond.map { Int(($0 / 1_000).rounded()) })) kbps",
            "path \(show(localCandidateType))",
        ].joined(separator: ", ")
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
