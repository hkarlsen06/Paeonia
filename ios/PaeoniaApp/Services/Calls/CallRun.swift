import Foundation

/// One call's state machine and the work that runs for it.
final class CallRun {
    var machine: CallMachine
    /// The id the system call UI knows. It stays put if the server's call id changes.
    let conversationID: UUID
    var role: CallMediaSession.Role
    var media: CallMediaSession?
    var timers: [CallTimer: Task<Void, Never>] = [:]
    var heartbeat: Task<Void, Never>?
    /// Tells the server the call ended here.
    var serverEnd: Task<Void, Never>?
    /// The end came from the system call UI, which already shows it.
    var isEndingFromSystem = false

    init(machine: CallMachine, conversationID: UUID, role: CallMediaSession.Role) {
        self.machine = machine
        self.conversationID = conversationID
        self.role = role
    }

    var callID: UUID {
        machine.callID
    }

    var isFinished: Bool {
        if case .ended = machine.phase {
            return true
        }
        return false
    }

    func stop() {
        for timer in timers.values {
            timer.cancel()
        }
        timers = [:]
        heartbeat?.cancel()
        heartbeat = nil
        media?.close()
        media = nil
    }
}
