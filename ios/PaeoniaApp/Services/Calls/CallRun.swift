import Foundation
@preconcurrency import LiveCommunicationKit

/// One call's state machine and the work that runs for it.
final class CallRun {
    var machine: CallMachine
    /// The id the system call UI knows. It stays put if the server's call id changes.
    let conversationID: UUID
    var role: CallMediaSession.Role
    var media: CallMediaSession?
    var timers: [CallTimer: Task<Void, Never>] = [:]
    var heartbeat: Task<Void, Never>?
    /// Reads the server's row while the call rings (`CallEngine.updateRingWatch`).
    var ringWatch: Task<Void, Never>?
    /// Tells the server the call ended here.
    var serverEnd: Task<Void, Never>?
    /// The end came from the system call UI, which already shows it.
    var isEndingFromSystem = false
    /// Waits while the ended sound plays, before the system hears the call ended.
    var goodbye: Task<Void, Never>?
    /// The partner's handle while their call rings only inside the app, because Paeonia was open on
    /// screen when it came in. The system does not know this call yet and shows no ring of its own.
    /// Nil once the system knows the call, and for an outgoing call.
    private(set) var unreportedRingHandle: Handle?
    /// `CallRinger`'s ring, while `unreportedRingHandle` is set.
    private var ringSound: Task<Void, Never>?

    init(machine: CallMachine, conversationID: UUID, role: CallMediaSession.Role) {
        self.machine = machine
        self.conversationID = conversationID
        self.role = role
    }

    /// Rings inside the app, without telling the system.
    func ringInApp(from handle: Handle) {
        unreportedRingHandle = handle
        ringSound = CallRinger.ring()
    }

    /// Stops the ring inside the app and returns its handle, for telling the system about the call.
    /// Nil when the system already knows it.
    func takeUnreportedRing() -> Handle? {
        ringSound?.cancel()
        ringSound = nil
        defer { unreportedRingHandle = nil }
        return unreportedRingHandle
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
        ringWatch?.cancel()
        ringWatch = nil
        media?.close()
        media = nil
        goodbye?.cancel()
        _ = takeUnreportedRing()
    }
}
