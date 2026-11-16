import Foundation

/// What this phone measures about a call's connection, and the report it sends when the call ends.
extension CallEngine {
    /// Logs how long the phones took to connect after the answer, once per call, under the
    /// `CallStats` category.
    func noteQuality(of run: CallRun, from previous: CallPhase) {
        let phase = run.machine.phase
        guard phase != previous else { return }
        let wasConnected = run.quality.answerToConnectedMilliseconds != nil
        run.quality.noteChange(from: previous, to: phase, at: .now)
        guard !wasConnected, let milliseconds = run.quality.answerToConnectedMilliseconds else { return }
        let side = run.machine.direction == .incoming ? "answered here" : "partner answered"
        CallStatsLog.note("connected \(milliseconds) ms after the answer (\(side))")
    }

    /// Sends the report once, without holding up the end of the call. A failed send is dropped.
    /// The server never had a call that was not registered, and a call answered on another
    /// device goes on there, which reports for this person.
    func sendQualityReport(of run: CallRun, reason: CallEndReason) {
        guard run.machine.isRegistered, reason != .answeredElsewhere else { return }
        run.quality.noteHeat(ProcessInfo.processInfo.thermalState)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let report = run.quality.report(endReason: reason, appBuild: build)
        let callID = run.callID
        Task { [backend] in
            try? await backend.reportQuality(callID: callID, report: report)
        }
    }
}
