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
    private var videoSentSeconds = 0.0
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
            if sample.video.bytesSent > previous.video.bytesSent {
                videoSentSeconds += elapsed
            }
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
            videoSentSeconds: videoSentSeconds.rounded(),
            videoReceivedSeconds: videoReceivedSeconds.rounded(),
            hottestThermalState: CallQualityReport.Heat(hottest),
            appBuild: appBuild
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
