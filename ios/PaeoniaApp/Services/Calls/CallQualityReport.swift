import Foundation

/// What this phone measured about one call's connection. The engine feeds it the call's phases
/// and the samples `CallStatsLog` reads, and turns it into the report the phone sends when the
/// call ends (`calls:report_call_quality`).
nonisolated struct CallQualityTally: Sendable {
    /// When this phone knew the call was answered: the person's tap on the answering phone, or
    /// the server's answer on the caller's. A caller that connects before the server says so
    /// counts no time.
    private var answeredAt: ContinuousClock.Instant?
    private var answerToConnected: Duration?
    private var reconnects = 0
    private var reconnectingSince: ContinuousClock.Instant?
    private var reconnecting = Duration.zero
    private var roundTripSeconds: [Double] = []
    private var path: CallMediaPath?
    /// Reset when the connection drops, so the gap is not counted as video.
    private var previous: CallStatsSample?
    private var latest: CallStatsSample?
    private var camera = SentVideoTally()
    private var screen = SentVideoTally()
    /// ScreenCaptureKit's pictures per second in each interval the screen sent.
    private var screenCapturedPerSecond: [Double] = []
    private var screenPixelFormat: String?
    private var partnerScreen = ReceivedScreenTally()
    private var videoReceivedSeconds = 0.0
    private var hottest = ProcessInfo.ThermalState.nominal

    /// The milliseconds from the answer to the first connection, once the call has connected.
    var answerToConnectedMilliseconds: Int? {
        answerToConnected.map { Int(($0 / .milliseconds(1)).rounded()) }
    }

    /// Keeps the first answer only.
    mutating func noteAnswer(at instant: ContinuousClock.Instant) {
        if answeredAt == nil {
            answeredAt = instant
        }
    }

    mutating func noteChange(from previousPhase: CallPhase, to phase: CallPhase, at instant: ContinuousClock.Instant) {
        if previousPhase == .ringing, phase == .connecting {
            noteAnswer(at: instant)
        }
        if case .active = phase, answerToConnected == nil {
            answerToConnected = instant - (answeredAt ?? instant)
        }
        if let reconnectingSince, !phase.isReconnecting {
            reconnecting += instant - reconnectingSince
            self.reconnectingSince = nil
        }
        if phase.isReconnecting, !previousPhase.isReconnecting {
            reconnects += 1
            reconnectingSince = instant
            previous = nil
        }
    }

    mutating func add(_ sample: CallStatsSample, thermalState: ProcessInfo.ThermalState) {
        noteHeat(thermalState)
        if let seconds = sample.roundTripSeconds {
            roundTripSeconds.append(seconds)
        }
        path = sample.mediaPath ?? path
        if let previous {
            let elapsed = max(sample.seconds - previous.seconds, 0)
            camera.add(sample.camera, since: previous.camera, elapsed: elapsed)
            if screen.add(sample.screen, since: previous.screen, elapsed: elapsed), elapsed > 0 {
                screenCapturedPerSecond.append(
                    Double(sample.screenCaptured.frames - previous.screenCaptured.frames) / elapsed
                )
                screenPixelFormat = sample.screenCaptured.pixelFormat ?? screenPixelFormat
            }
            partnerScreen.add(sample.screenReceived, since: previous.screenReceived, elapsed: elapsed)
            if sample.videoReceived.bytesReceived > previous.videoReceived.bytesReceived {
                videoReceivedSeconds += elapsed
            }
        }
        previous = sample
        latest = sample
    }

    mutating func noteHeat(_ thermalState: ProcessInfo.ThermalState) {
        if thermalState.rawValue > hottest.rawValue {
            hottest = thermalState
        }
    }

    func report(endReason: CallEndReason, appBuild: String) -> CallQualityReport {
        CallQualityReport(
            endReason: CallQualityReport.EndReason(endReason),
            mediaConnected: answerToConnected != nil,
            answerToConnectedMilliseconds: answerToConnectedMilliseconds,
            path: path.map { $0 == .direct ? .direct : .turn },
            reconnects: reconnects,
            reconnectingSeconds: (reconnecting / .milliseconds(100)).rounded() / 10,
            medianRoundTripMilliseconds: Self.median(roundTripSeconds).map { ($0 * 1_000).rounded() },
            audioLossPercent: latest?.audioReceived.lossPercent.map(Self.oneDecimal),
            videoLossPercent: latest?.videoReceived.lossPercent.map(Self.oneDecimal),
            videoSentSeconds: camera.seconds.rounded(),
            videoReceivedSeconds: videoReceivedSeconds.rounded(),
            hottestThermalState: CallQualityReport.Heat(hottest),
            appBuild: appBuild,
            videoSentFramesPerSecond: Self.median(camera.framesPerSecond).map(Self.oneDecimal),
            videoLimits: camera.limits,
            screenSentSeconds: screen.seconds > 0 ? screen.seconds.rounded() : nil,
            screenCapturedFramesPerSecond: Self.median(screenCapturedPerSecond).map(Self.oneDecimal),
            screenSentFramesPerSecond: Self.median(screen.framesPerSecond).map(Self.oneDecimal),
            screenSourceFramesPerSecond: Self.median(screen.sourceFramesPerSecond).map(Self.oneDecimal),
            screenSentWidth: Self.median(screen.widths).map { Int($0.rounded()) },
            screenSentHeight: Self.median(screen.heights).map { Int($0.rounded()) },
            screenLimits: screen.limits,
            screenEncodeMilliseconds: screen.encodeMilliseconds.map(Self.oneDecimal),
            screenQuantizer: screen.averageQuantizer.map(Self.oneDecimal),
            screenKeyFramesPerMinute: screen.keyFramesPerMinute.map(Self.oneDecimal),
            screenEncoder: screen.encoderImplementation,
            screenPowerEfficientEncoder: screen.isPowerEfficientEncoder,
            screenPixelFormat: screenPixelFormat,
            screenReceivedSeconds: partnerScreen.seconds > 0 ? partnerScreen.seconds.rounded() : nil,
            screenReceivedFramesPerSecond: Self.median(partnerScreen.framesPerSecond).map(Self.oneDecimal),
            screenFramesDropped: partnerScreen.seconds > 0 ? partnerScreen.framesDropped : nil,
            screenFreezes: partnerScreen.seconds > 0 ? partnerScreen.freezes : nil,
            screenDecodeMilliseconds: partnerScreen.decodeMilliseconds.map(Self.oneDecimal),
            encoderResets: latest?.encoderTrouble.resets,
            encoderFailedFrames: latest?.encoderTrouble.failedFrames,
            encoderDroppedFrames: latest?.encoderTrouble.droppedFrames
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func oneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// What one video stream this phone sends did in the intervals between samples in which it sent.
private nonisolated struct SentVideoTally: Sendable {
    var seconds = 0.0
    /// Each interval's frames over its seconds, from WebRTC's counters: those it encoded, and
    /// those that went into it for the encoder.
    var framesPerSecond: [Double] = []
    var widths: [Double] = []
    var heights: [Double] = []
    var sourceFramesPerSecond: [Double] = []
    /// Seconds per limit from WebRTC's `qualityLimitationDurations`, and samples per limit for
    /// when WebRTC leaves those out.
    var secondsPerLimit: [CallQualityReport.Limit: Double] = [:]
    var samplesPerLimit: [CallQualityReport.Limit: Double] = [:]
    var framesEncoded = 0
    var encodeSeconds = 0.0
    var keyFramesEncoded = 0
    var qpSum = 0
    var encoderImplementation: String?
    var isPowerEfficientEncoder: Bool?

    var limits: CallQualityReport.Limits? {
        CallQualityReport.Limits(secondsPerLimit) ?? CallQualityReport.Limits(samplesPerLimit)
    }

    var encodeMilliseconds: Double? {
        CallStatsSample.millisecondsPerFrame(seconds: encodeSeconds, frames: framesEncoded)
    }

    var averageQuantizer: Double? {
        framesEncoded > 0 ? Double(qpSum) / Double(framesEncoded) : nil
    }

    var keyFramesPerMinute: Double? {
        seconds > 0 ? Double(keyFramesEncoded) / seconds * 60 : nil
    }

    /// Returns whether the stream sent since `before`.
    @discardableResult
    mutating func add(
        _ now: CallStatsSample.SentVideo,
        since before: CallStatsSample.SentVideo,
        elapsed: Double
    ) -> Bool {
        guard now.sent.bytesSent > before.sent.bytesSent else { return false }
        seconds += elapsed
        if elapsed > 0, let frames = now.framesEncoded(since: before) {
            framesPerSecond.append(Double(frames) / elapsed)
        }
        if elapsed > 0, let frames = now.sourceFrames(since: before) {
            sourceFramesPerSecond.append(Double(frames) / elapsed)
        }
        if let width = now.frameWidth, let height = now.frameHeight {
            widths.append(Double(width))
            heights.append(Double(height))
        }
        if let reason = now.qualityLimitation {
            samplesPerLimit[CallQualityReport.Limit(reason), default: 0] += 1
        }
        for (reason, total) in now.limitationSeconds {
            secondsPerLimit[CallQualityReport.Limit(reason), default: 0] +=
                max(total - (before.limitationSeconds[reason] ?? 0), 0)
        }
        let frames = now.framesEncoded - before.framesEncoded
        if frames > 0 {
            framesEncoded += frames
            encodeSeconds += max(now.encodeSeconds - before.encodeSeconds, 0)
            qpSum += max(now.qpSum - before.qpSum, 0)
        }
        keyFramesEncoded += max(now.keyFramesEncoded - before.keyFramesEncoded, 0)
        encoderImplementation = now.encoderImplementation ?? encoderImplementation
        isPowerEfficientEncoder = now.isPowerEfficientEncoder ?? isPowerEfficientEncoder
        return true
    }
}

/// What this phone received of the partner's shared screen in the intervals in which it arrived.
private nonisolated struct ReceivedScreenTally: Sendable {
    var seconds = 0.0
    /// Each interval's decoded frames over its seconds.
    var framesPerSecond: [Double] = []
    var framesDropped = 0
    var freezes = 0
    var framesDecoded = 0
    var decodeSeconds = 0.0

    var decodeMilliseconds: Double? {
        CallStatsSample.millisecondsPerFrame(seconds: decodeSeconds, frames: framesDecoded)
    }

    mutating func add(
        _ now: CallStatsSample.ReceivedScreen,
        since before: CallStatsSample.ReceivedScreen,
        elapsed: Double
    ) {
        guard now.bytesReceived > before.bytesReceived else { return }
        seconds += elapsed
        if elapsed > 0, now.framesDecoded >= before.framesDecoded {
            framesPerSecond.append(Double(now.framesDecoded - before.framesDecoded) / elapsed)
        }
        framesDropped += max(now.framesDropped - before.framesDropped, 0)
        freezes += max(now.freezes - before.freezes, 0)
        let frames = now.framesDecoded - before.framesDecoded
        if frames > 0 {
            framesDecoded += frames
            decodeSeconds += max(now.decodeSeconds - before.decodeSeconds, 0)
        }
    }
}

/// The report `calls:report_call_quality` stores. Facts about the connection only. A field this
/// phone could not measure is left out.
nonisolated struct CallQualityReport: Encodable, Equatable, Sendable {
    enum EndReason: String, Encodable, Sendable {
        case hungUp = "hung_up"
        case noAnswer = "no_answer"
        case missed
        case answeredElsewhere = "answered_elsewhere"
        case busy
        case offline
        case couldNotConnect = "could_not_connect"
        case microphoneDenied = "microphone_denied"
        case notPartner = "not_partner"
        case other

        init(_ reason: CallEndReason) {
            self = switch reason {
            case .hungUp: .hungUp
            case .noAnswer: .noAnswer
            case .missed: .missed
            case .answeredElsewhere: .answeredElsewhere
            case .busy: .busy
            case let .failed(failure): Self(failure)
            }
        }

        init(_ failure: CallFailure) {
            self = switch failure {
            case .offline: .offline
            case .couldNotConnect: .couldNotConnect
            case .microphoneDenied: .microphoneDenied
            case .notPartner: .notPartner
            case .other: .other
            }
        }
    }

    enum Path: String, Encodable, Sendable {
        case direct
        case turn
    }

    enum Heat: String, Encodable, Sendable {
        case nominal
        case fair
        case serious
        case critical

        init(_ state: ProcessInfo.ThermalState) {
            self = switch state {
            case .nominal: .nominal
            case .fair: .fair
            case .serious: .serious
            case .critical: .critical
            @unknown default: .critical
            }
        }
    }

    /// What kept a video encoder from sending more, as WebRTC's `qualityLimitationReason` says.
    enum Limit: String, Sendable {
        case cpu
        case bandwidth
        case other
        case none

        init(_ reason: String) {
            self = Self(rawValue: reason) ?? .other
        }
    }

    /// The percent of the time a stream sent in which each limit held, or of its samples when WebRTC
    /// gives no durations. Rounding can make the sum 99 or 101.
    struct Limits: Encodable, Equatable, Sendable {
        let cpu: Int
        let bandwidth: Int
        let other: Int
        let none: Int

        /// Nil when nothing was measured.
        init?(_ amountPerLimit: [Limit: Double]) {
            let total = amountPerLimit.values.reduce(0, +)
            guard total > 0 else { return nil }
            func percent(_ limit: Limit) -> Int {
                Int((amountPerLimit[limit, default: 0] / total * 100).rounded())
            }
            cpu = percent(.cpu)
            bandwidth = percent(.bandwidth)
            other = percent(.other)
            none = percent(.none)
        }
    }

    let endReason: EndReason
    let mediaConnected: Bool
    let answerToConnectedMilliseconds: Int?
    let path: Path?
    let reconnects: Int
    let reconnectingSeconds: Double
    let medianRoundTripMilliseconds: Double?
    let audioLossPercent: Double?
    let videoLossPercent: Double?
    let videoSentSeconds: Double
    let videoReceivedSeconds: Double
    let hottestThermalState: Heat
    let appBuild: String
    /// The camera's and the shared screens' numbers are left out when that video did not run.
    let videoSentFramesPerSecond: Double?
    let videoLimits: Limits?
    let screenSentSeconds: Double?
    let screenCapturedFramesPerSecond: Double?
    let screenSentFramesPerSecond: Double?
    let screenSourceFramesPerSecond: Double?
    let screenSentWidth: Int?
    let screenSentHeight: Int?
    let screenLimits: Limits?
    let screenEncodeMilliseconds: Double?
    let screenQuantizer: Double?
    let screenKeyFramesPerMinute: Double?
    let screenEncoder: String?
    let screenPowerEfficientEncoder: Bool?
    let screenPixelFormat: String?
    let screenReceivedSeconds: Double?
    let screenReceivedFramesPerSecond: Double?
    let screenFramesDropped: Int?
    let screenFreezes: Int?
    let screenDecodeMilliseconds: Double?
    /// The camera's and the screen's encoders together, for the whole call.
    let encoderResets: Int?
    let encoderFailedFrames: Int?
    let encoderDroppedFrames: Int?

    enum CodingKeys: String, CodingKey {
        case endReason = "end_reason"
        case mediaConnected = "media_connected"
        case answerToConnectedMilliseconds = "answer_to_connected_ms"
        case path
        case reconnects
        case reconnectingSeconds = "reconnecting_seconds"
        case medianRoundTripMilliseconds = "median_rtt_ms"
        case audioLossPercent = "audio_loss_percent"
        case videoLossPercent = "video_loss_percent"
        case videoSentSeconds = "video_sent_seconds"
        case videoReceivedSeconds = "video_received_seconds"
        case hottestThermalState = "hottest_thermal_state"
        case appBuild = "app_build"
        case videoSentFramesPerSecond = "video_sent_fps"
        case videoLimits = "video_limits"
        case screenSentSeconds = "screen_sent_seconds"
        case screenCapturedFramesPerSecond = "screen_captured_fps"
        case screenSentFramesPerSecond = "screen_sent_fps"
        case screenSourceFramesPerSecond = "screen_source_fps"
        case screenSentWidth = "screen_sent_width"
        case screenSentHeight = "screen_sent_height"
        case screenLimits = "screen_limits"
        case screenEncodeMilliseconds = "screen_encode_ms"
        case screenQuantizer = "screen_qp"
        case screenKeyFramesPerMinute = "screen_key_frames_per_minute"
        case screenEncoder = "screen_encoder"
        case screenPowerEfficientEncoder = "screen_power_efficient_encoder"
        case screenPixelFormat = "screen_pixel_format"
        case screenReceivedSeconds = "screen_received_seconds"
        case screenReceivedFramesPerSecond = "screen_received_fps"
        case screenFramesDropped = "screen_frames_dropped"
        case screenFreezes = "screen_freezes"
        case screenDecodeMilliseconds = "screen_decode_ms"
        case encoderResets = "encoder_resets"
        case encoderFailedFrames = "encoder_failed_frames"
        case encoderDroppedFrames = "encoder_dropped_frames"
    }
}

private nonisolated extension CallPhase {
    var isReconnecting: Bool {
        if case .reconnecting = self {
            return true
        }
        return false
    }
}
