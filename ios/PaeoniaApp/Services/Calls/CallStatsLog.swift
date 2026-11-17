import Foundation
import OSLog
import Synchronization
@preconcurrency import LiveKitWebRTC

/// Reads the call's media stats every 2 seconds while the phones are connected, and logs one line
/// about them every 10 seconds: codecs, bitrates, losses, round trip time and whether the media
/// goes direct or through TURN, and how the camera and the shared screens keep up. Read it in
/// Console with the `CallStats` category. Each sample also goes to `onSample`, the first one as
/// soon as the phones connect, so the call can notice a weak connection within seconds
/// (`CallConnectionHealth`).
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
    private let encoderTrouble = CallEncoderTrouble()
    private let webRTCLog = LKRTCCallbackLogger()

    init(
        sampleInterval: Duration = .seconds(2),
        lineInterval: Duration = .seconds(10),
        write: @escaping (String) -> Void = { logger.notice("\($0, privacy: .public)") }
    ) {
        self.sampleInterval = sampleInterval
        self.lineInterval = lineInterval
        self.write = write
    }

    /// `screenCaptured` reads what ScreenCaptureKit has handed this phone's share so far.
    func start(
        _ peerConnection: LKRTCPeerConnection,
        screenCaptured: @escaping () -> CallStatsSample.Captured = { CallStatsSample.Captured() },
        onSample: @escaping (CallStatsSample) -> Void = { _ in }
    ) {
        guard task == nil else { return }
        let lineSeconds = Double(lineInterval.components.seconds)
        // The H.265 encoder logs its resets and dropped frames as info.
        webRTCLog.severity = .info
        webRTCLog.start(encoderTrouble.countHandler)
        task = Task { [sampleInterval, write, encoderTrouble] in
            func read() async -> CallStatsSample {
                var sample = await CallStatsSample.read(peerConnection)
                sample.screenCaptured = screenCaptured()
                sample.encoderTrouble = encoderTrouble.counts
                return sample
            }
            var lastLine = await read()
            onSample(lastLine)
            while true {
                try? await Task.sleep(for: sampleInterval)
                guard !Task.isCancelled else { return }
                let current = await read()
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
        webRTCLog.stop()
    }
}

/// Counts the video encoders' trouble in WebRTC's own log, for the whole call. The lines come
/// from VideoToolbox's encoders in webrtc-sdk m150 (`RTCVideoEncoderH265.mm` and
/// `RTCVideoEncoderH264.mm`). WebRTC calls the handler on the thread that logs, which can be the
/// encoder's, so it only compares and adds.
private nonisolated final class CallEncoderTrouble: Sendable {
    private let resets = Atomic(0)
    private let failedFrames = Atomic(0)
    private let droppedFrames = Atomic(0)

    var counts: CallStatsSample.EncoderTrouble {
        CallStatsSample.EncoderTrouble(
            resets: resets.load(ordering: .relaxed),
            failedFrames: failedFrames.load(ordering: .relaxed),
            droppedFrames: droppedFrames.load(ordering: .relaxed)
        )
    }

    /// Made here, outside the main actor, so WebRTC's threads may call it.
    var countHandler: @Sendable (String) -> Void {
        { [self] message in count(message) }
    }

    private func count(_ message: String) {
        // WebRTC's own encoder wrapper logs "Failed to encode frame. Error code:" for the same
        // failure, so only VideoToolbox's wording counts.
        if message.contains("Resetting compression session") || message.contains("Invalid compression session") {
            resets.add(1, ordering: .relaxed)
        } else if message.contains("Failed to encode frame with code") || message.contains("h265 encode failed")
            || message.contains("H264 encode failed") {
            failedFrames.add(1, ordering: .relaxed)
        } else if message.contains("dropped a frame") || message.contains("H264 encode dropped frame") {
            droppedFrames.add(1, ordering: .relaxed)
        }
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

    /// One video stream this phone sends, the camera's or the screen's.
    nonisolated struct SentVideo: Sendable {
        var sent = Outbound()
        var frameWidth: Int?
        var frameHeight: Int?
        /// WebRTC's count of the frames encoded in the last second, a snapshot that a screen
        /// changing in bursts swings. `framesEncoded` over time is the steady rate.
        var framesPerSecond: Double?
        /// `none`, `cpu`, `bandwidth` or `other`: what keeps the encoder from sending more.
        var qualityLimitation: String?
        var framesEncoded = 0
        var encodeSeconds = 0.0
        /// The frames that went into WebRTC for the encoder, from the stream's `media-source`.
        /// Those it encoded count in `framesEncoded`, and the rest it dropped on the way.
        var sourceFrames = 0
        var keyFramesEncoded = 0
        /// The sum of the frames' quantizers. Higher means coarser pictures.
        var qpSum = 0
        var encoderImplementation: String?
        var isPowerEfficientEncoder: Bool?
        /// The seconds each `qualityLimitation` held since the stream began.
        var limitationSeconds: [String: Double] = [:]
    }

    /// How often the phone's video encoders reset, failed a frame or dropped one, since the call
    /// started. These count the camera and the screen together.
    nonisolated struct EncoderTrouble: Sendable {
        var resets = 0
        var failedFrames = 0
        var droppedFrames = 0
    }

    /// The partner's shared screen as this phone receives it, since the call started.
    nonisolated struct ReceivedScreen: Sendable {
        var bytesReceived = 0
        var framesDropped = 0
        var freezes = 0
        var framesDecoded = 0
        var decodeSeconds = 0.0
    }

    /// The pictures ScreenCaptureKit handed this phone's shares since the app started.
    nonisolated struct Captured: Sendable {
        var frames = 0
        /// The pixel format of its buffers as a four-character code, such as `420f`.
        var pixelFormat: String?
    }

    var seconds: Double
    var audio = Outbound()
    var camera = SentVideo()
    /// This phone's shared screen, which has its own video stream.
    var screen = SentVideo()
    var screenCaptured = Captured()
    var encoderTrouble = EncoderTrouble()
    /// Video packets the partner's phone asked for again, so they were lost on the way.
    var videoNacks = 0
    var videoBytesResent = 0
    /// How unevenly the camera's packets reach the partner's phone. WebRTC sends less when the
    /// delay grows, even when nothing is lost.
    var partnerJitterSeconds: Double?
    var audioReceived = Inbound()
    /// The partner's camera, and their shared screen while they share it.
    var videoReceived = Inbound()
    /// The partner's shared screen alone. It counts in `videoReceived` too.
    var screenReceived = ReceivedScreen()
    /// What the partner's phone reports it never got of what this phone sent, audio, camera and
    /// screen together, from their receiver reports. It lags `packetsSent` by up to a report
    /// interval.
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
        // The screen's transceiver is the second video one (`CallMediaSession.addTransceivers`).
        let screenMid = peerConnection.transceivers.filter { $0.mediaType == .video }.dropFirst().first?.mid
        return await withCheckedContinuation { continuation in
            peerConnection.statistics { continuation.resume(returning: CallStatsSample($0, screenMid: screenMid)) }
        }
    }

    init(_ report: LKRTCStatisticsReport, screenMid: String?) {
        let stats = report.statistics
        seconds = report.timestamp_us / 1_000_000
        for stat in stats.values {
            switch stat.type {
            case "outbound-rtp":
                readSent(stat, in: stats, screenMid: screenMid)
            case "remote-inbound-rtp":
                packetsLostAtPartner += Int(stat.number("packetsLost") ?? 0)
                let isCamera = stat.string("kind") == "video"
                    && (screenMid == nil || stats[stat.string("localId") ?? ""]?.string("mid") != screenMid)
                partnerJitterSeconds = isCamera ? stat.number("jitter") : partnerJitterSeconds
            case "inbound-rtp":
                readReceived(stat, screenMid: screenMid)
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

    /// Sorts one sent stream into the audio, the camera or the screen.
    private mutating func readSent(_ stat: LKRTCStatistics, in stats: [String: LKRTCStatistics], screenMid: String?) {
        let sent = Outbound(
            codec: stats[stat.string("codecId") ?? ""]?.string("mimeType"),
            bytesSent: Int(stat.number("bytesSent") ?? 0),
            packetsSent: Int(stat.number("packetsSent") ?? 0),
            targetBitsPerSecond: stat.number("targetBitrate")
        )
        guard stat.string("kind") == "video" else {
            audio = sent
            return
        }
        let video = SentVideo(
            sent: sent,
            frameWidth: stat.number("frameWidth").map { Int($0) },
            frameHeight: stat.number("frameHeight").map { Int($0) },
            framesPerSecond: stat.number("framesPerSecond"),
            qualityLimitation: stat.string("qualityLimitationReason"),
            framesEncoded: Int(stat.number("framesEncoded") ?? 0),
            encodeSeconds: stat.number("totalEncodeTime") ?? 0,
            sourceFrames: Int(stats[stat.string("mediaSourceId") ?? ""]?.number("frames") ?? 0),
            keyFramesEncoded: Int(stat.number("keyFramesEncoded") ?? 0),
            qpSum: Int(stat.number("qpSum") ?? 0),
            encoderImplementation: stat.string("encoderImplementation"),
            isPowerEfficientEncoder: (stat.values["powerEfficientEncoder"] as? NSNumber)?.boolValue,
            limitationSeconds: (stat.values["qualityLimitationDurations"] as? [String: NSNumber])?
                .mapValues(\.doubleValue) ?? [:]
        )
        if let screenMid, stat.string("mid") == screenMid {
            screen = video
            return
        }
        camera = video
        videoNacks = Int(stat.number("nackCount") ?? 0)
        videoBytesResent = Int(stat.number("retransmittedBytesSent") ?? 0)
    }

    /// Adds one received stream to the audio or the video, and keeps the partner's screen apart too.
    private mutating func readReceived(_ stat: LKRTCStatistics, screenMid: String?) {
        guard stat.string("kind") == "video" else {
            audioReceived.add(Inbound(stat))
            return
        }
        videoReceived.add(Inbound(stat))
        if let screenMid, stat.string("mid") == screenMid {
            screenReceived = ReceivedScreen(stat)
        }
    }

    /// The milliseconds each frame took on average, from the growth of two running totals, or nil
    /// when no frame was done.
    static func millisecondsPerFrame(seconds: Double, frames: Int) -> Double? {
        frames > 0 ? max(seconds, 0) / Double(frames) * 1_000 : nil
    }

    /// One log line with the rates since `previous`.
    func line(since previous: CallStatsSample) -> String {
        let elapsed = max(seconds - previous.seconds, 0.001)
        let captured = Double(screenCaptured.frames - previous.screenCaptured.frames) / elapsed
        return [
            "audio \(show(audio.codec)) \(kbps(audio.bytesSent, previous.audio.bytesSent, elapsed)) kbps",
            "video \(show(camera.sent.codec)) \(camera.line(since: previous.camera, elapsed: elapsed))"
                + ", resent \(kbps(videoBytesResent, previous.videoBytesResent, elapsed)) kbps"
                + " (\(videoNacks - previous.videoNacks) asked)"
                + ", jitter at partner \(whole(partnerJitterSeconds.map { $0 * 1_000 })) ms",
            "screen \(screen.line(since: previous.screen, elapsed: elapsed))"
                + ", captured \(whole(captured)) fps \(show(screenCaptured.pixelFormat))",
            "partner screen \(screenReceived.line(since: previous.screenReceived, elapsed: elapsed))",
            "encoder resets \(encoderTrouble.resets - previous.encoderTrouble.resets)"
                + " failed \(encoderTrouble.failedFrames - previous.encoderTrouble.failedFrames)"
                + " dropped \(encoderTrouble.droppedFrames - previous.encoderTrouble.droppedFrames)",
            "receive \(kbps(bytesReceived, previous.bytesReceived, elapsed)) kbps",
            "lost \(packetsLost - previous.packetsLost)",
            "rtt \(whole(roundTripSeconds.map { $0 * 1_000 })) ms",
            "available \(whole(availableOutgoingBitsPerSecond.map { $0 / 1_000 })) kbps",
            "path \(show(localCandidateType))/\(show(remoteCandidateType))",
        ].joined(separator: ", ")
    }
}

private nonisolated extension CallStatsSample.SentVideo {
    func line(since earlier: Self, elapsed: Double) -> String {
        let frame = frameWidth.flatMap { width in frameHeight.map { "\(width)x\($0)" } }
        let frames = framesEncoded - earlier.framesEncoded
        let encode = CallStatsSample.millisecondsPerFrame(
            seconds: encodeSeconds - earlier.encodeSeconds,
            frames: frames
        )
        let quantizer = frames > 0 ? Double(qpSum - earlier.qpSum) / Double(frames) : nil
        let encoder = show(encoderImplementation) + (isPowerEfficientEncoder == true ? " efficient" : "")
        return "\(kbps(sent.bytesSent, earlier.sent.bytesSent, elapsed)) kbps"
            + " (target \(whole(sent.targetBitsPerSecond.map { $0 / 1_000 })))"
            + " \(show(frame)) \(rate(sourceFrames - earlier.sourceFrames, elapsed)) fps in"
            + " \(rate(frames, elapsed)) out"
            + " encode \(whole(encode)) ms qp \(whole(quantizer)) key \(keyFramesEncoded - earlier.keyFramesEncoded)"
            + " by \(encoder) limit \(show(qualityLimitation))"
    }
}

private nonisolated extension CallStatsSample.ReceivedScreen {
    func line(since earlier: Self, elapsed: Double) -> String {
        let decode = CallStatsSample.millisecondsPerFrame(
            seconds: decodeSeconds - earlier.decodeSeconds,
            frames: framesDecoded - earlier.framesDecoded
        )
        return "\(kbps(bytesReceived, earlier.bytesReceived, elapsed)) kbps"
            + " \(rate(framesDecoded - earlier.framesDecoded, elapsed)) fps"
            + " decode \(whole(decode)) ms"
            + ", dropped \(framesDropped - earlier.framesDropped) froze \(freezes - earlier.freezes)"
    }
}

private nonisolated func kbps(_ bytes: Int, _ earlier: Int, _ elapsed: Double) -> Int {
    Int((Double(bytes - earlier) * 8 / elapsed / 1_000).rounded())
}

private nonisolated func rate(_ frames: Int, _ elapsed: Double) -> String {
    elapsed > 0 ? whole(Double(frames) / elapsed) : "-"
}

private nonisolated func show(_ value: (some Any)?) -> String {
    value.map { "\($0)" } ?? "-"
}

private nonisolated func whole(_ value: Double?) -> String {
    show(value.map { Int($0.rounded()) })
}

private nonisolated extension CallStatsSample.Inbound {
    init(_ stat: LKRTCStatistics) {
        bytesReceived = Int(stat.number("bytesReceived") ?? 0)
        packetsReceived = Int(stat.number("packetsReceived") ?? 0)
        packetsLost = Int(stat.number("packetsLost") ?? 0)
    }
}

private nonisolated extension CallStatsSample.ReceivedScreen {
    init(_ stat: LKRTCStatistics) {
        bytesReceived = Int(stat.number("bytesReceived") ?? 0)
        framesDropped = Int(stat.number("framesDropped") ?? 0)
        freezes = Int(stat.number("freezeCount") ?? 0)
        framesDecoded = Int(stat.number("framesDecoded") ?? 0)
        decodeSeconds = stat.number("totalDecodeTime") ?? 0
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
