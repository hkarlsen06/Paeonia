import Foundation

/// The couple's visits and list as the server last sent them, for one signed-in person, so
/// the Us tab card and the visit screen show them offline and right after launch. It also
/// keeps this person's refused writes until a screen shows them, and the day the "When do
/// you meet next?" card comes back after they hid it.
protocol VisitsCaching: Actor {
    func state(ownerUserID: UUID) -> VisitsLocalState
    func store(_ state: VisitsLocalState, ownerUserID: UUID)
    /// Called when the person leaves the paired state, so nothing stays on the phone.
    func clearAll()
}

/// What one person keeps about visits on this phone.
nonisolated struct VisitsLocalState: Codable, Equatable, Sendable {
    var visits = CoupleVisits()
    /// Writes the server refused for good that no screen has shown yet.
    var refusals: [VisitsRefusal] = []
    var promptReturnDay: LockScreenCalendarDate?
    /// Rows the live feed dropped, newest last, so a write confirmed after a partner deleted
    /// the row doesn't bring it back. Only a write in flight needs them, so few are kept.
    var removedByFeed: [UUID] = []

    static let removedByFeedLimit = 200
}

extension VisitsCaching {
    /// The live feed's write. It notes the rows it drops.
    func save(_ visits: CoupleVisits, ownerUserID: UUID) {
        update(ownerUserID) { state in
            let kept = Set(visits.visits.map(\.id) + visits.items.map(\.id))
            let dropped = (state.visits.visits.map(\.id) + state.visits.items.map(\.id)).filter { !kept.contains($0) }
            let removed = state.removedByFeed.filter { !kept.contains($0) && !dropped.contains($0) } + dropped
            state.removedByFeed = Array(removed.suffix(VisitsLocalState.removedByFeedLimit))
            state.visits = visits
        }
    }

    /// A row the server confirmed after a write, applied before the live feed brings the same change.
    func confirm(_ confirmation: VisitsConfirmation, ownerUserID: UUID) {
        update(ownerUserID) { state in
            state.visits = state.visits.confirming(confirmation, removedByFeed: Set(state.removedByFeed))
        }
    }

    func recordRefusal(_ refusal: VisitsRefusal, ownerUserID: UUID) {
        update(ownerUserID) { $0.refusals.append(refusal) }
    }

    /// Forgets `shown`, once a screen told the person about them.
    func removeRefusals(_ shown: [VisitsRefusal], ownerUserID: UUID) {
        update(ownerUserID) { state in
            for refusal in shown {
                if let index = state.refusals.firstIndex(of: refusal) { state.refusals.remove(at: index) }
            }
        }
    }

    func setPromptReturnDay(_ day: LockScreenCalendarDate, ownerUserID: UUID) {
        update(ownerUserID) { $0.promptReturnDay = day }
    }

    private func update(_ ownerUserID: UUID, _ change: (inout VisitsLocalState) -> Void) {
        var state = state(ownerUserID: ownerUserID)
        change(&state)
        store(state, ownerUserID: ownerUserID)
    }
}

actor FileVisitsCache: VisitsCaching {
    static let shared = FileVisitsCache()

    /// Bump when a stored type gains a required field. A file with another version reads as empty.
    private static let schemaVersion = 3

    private let directoryURL: URL

    init(directoryURL: URL = FileVisitsCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisitsCache", isDirectory: true)
    }

    func state(ownerUserID: UUID) -> VisitsLocalState {
        guard let data = try? Data(contentsOf: fileURL(for: ownerUserID)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.ownerUserID == ownerUserID
        else {
            return VisitsLocalState()
        }
        return envelope.state
    }

    func store(_ state: VisitsLocalState, ownerUserID: UUID) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, ownerUserID: ownerUserID, state: state)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: ownerUserID), options: [.atomic])
    }

    func clearAll() {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func fileURL(for ownerUserID: UUID) -> URL {
        directoryURL.appendingPathComponent(ownerUserID.uuidString.lowercased() + ".json", isDirectory: false)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerUserID: UUID
        let state: VisitsLocalState
    }
}

/// A cache that lives in memory, for the developer scenarios and tests.
actor InMemoryVisitsCache: VisitsCaching {
    private var stored: [UUID: VisitsLocalState]

    init(_ visits: CoupleVisits = CoupleVisits(), ownerUserID: UUID? = nil) {
        stored = ownerUserID.map { [$0: VisitsLocalState(visits: visits)] } ?? [:]
    }

    func state(ownerUserID: UUID) -> VisitsLocalState {
        stored[ownerUserID] ?? VisitsLocalState()
    }

    func store(_ state: VisitsLocalState, ownerUserID: UUID) {
        stored[ownerUserID] = state
    }

    func clearAll() {
        stored.removeAll()
    }
}
