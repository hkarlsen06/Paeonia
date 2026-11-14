import SwiftUI

/// What the call is doing, in a few words: "Calling…", the running call time, or why it ended.
struct CallStatusLine: View {
    let phase: CallPhase
    var font: Font = PaeoniaTypography.body

    var body: some View {
        Group {
            switch phase {
            case let .active(since):
                // Counts every second from when the call was answered.
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(verbatim: Self.elapsed(since: since, now: context.date))
                        .monospacedDigit()
                }
            default:
                if let text = Self.text(for: phase) { Text(text) }
            }
        }
        .font(font)
        .foregroundStyle(.paeoniaTextSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)
    }

    /// The line for every phase but a running call, which shows its time instead.
    static func text(for phase: CallPhase) -> LocalizedStringResource? {
        switch phase {
        case .ringing: .callsStatusCalling
        case .connecting: .callsStatusConnecting
        case .active: nil
        case .reconnecting: .callsStatusReconnecting
        case let .ended(reason): text(for: reason)
        }
    }

    static func text(for reason: CallEndReason) -> LocalizedStringResource {
        switch reason {
        case .hungUp: .callsEndedHungUp
        case .noAnswer: .callsEndedNoAnswer
        case .missed: .callsEndedMissed
        case .answeredElsewhere: .callsEndedAnsweredElsewhere
        case .busy: .callsEndedBusy
        case let .failed(failure): text(for: failure)
        }
    }

    /// Only `offline` talks about the connection. The rest can happen on a working one.
    static func text(for failure: CallFailure) -> LocalizedStringResource {
        switch failure {
        case .offline: .callsFailedOffline
        case .couldNotConnect: .callsFailedCouldNotConnect
        case .microphoneDenied: .callsFailedMicrophone
        case .notPartner: .callsFailedNotPartner
        case .other: .callsFailedOther
        }
    }

    /// "4:07", or "1:02:09" past an hour.
    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let duration = Duration.seconds(seconds)
        return seconds >= 3_600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }
}
