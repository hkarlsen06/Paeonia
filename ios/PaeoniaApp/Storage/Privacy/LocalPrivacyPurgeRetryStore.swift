import Foundation

nonisolated enum LocalPrivacyPurgeResult: Equatable, Sendable {
    case completed
    case recordsPendingRetry
    case recordsFailedWithoutDurableRetry

    var isComplete: Bool {
        self == .completed
    }
}

nonisolated enum LocalPrivacyPurgeRetryResult: Equatable, Sendable {
    case completed
    case recordsPendingRetry
}

nonisolated struct LocalPrivacyPurgeRequest: Codable, Equatable, Sendable {
    let ownerUserID: UUID
    let scope: LocalPrivacyPurgeScope

    nonisolated func merging(_ other: LocalPrivacyPurgeRequest) -> LocalPrivacyPurgeRequest {
        precondition(ownerUserID == other.ownerUserID)
        return LocalPrivacyPurgeRequest(
            ownerUserID: ownerUserID,
            scope: scope.merging(other.scope)
        )
    }
}

nonisolated protocol LocalPrivacyPurgeRetryStoring: Actor {
    func enqueue(_ request: LocalPrivacyPurgeRequest) throws
    func pendingRequests() throws -> [LocalPrivacyPurgeRequest]
    func request(for ownerUserID: UUID) throws -> LocalPrivacyPurgeRequest?
    func remove(_ completedRequest: LocalPrivacyPurgeRequest) throws
}

actor UserDefaultsLocalPrivacyPurgeRetryStore: LocalPrivacyPurgeRetryStoring {
    private static let storageKey = "privacy.pendingRecordPurges.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func enqueue(_ request: LocalPrivacyPurgeRequest) throws {
        var requests = try load()
        if let existing = requests[request.ownerUserID] {
            requests[request.ownerUserID] = existing.merging(request)
        } else {
            requests[request.ownerUserID] = request
        }
        try save(requests)
    }

    func pendingRequests() throws -> [LocalPrivacyPurgeRequest] {
        try load().values.sorted {
            $0.ownerUserID.uuidString < $1.ownerUserID.uuidString
        }
    }

    func request(for ownerUserID: UUID) throws -> LocalPrivacyPurgeRequest? {
        try load()[ownerUserID]
    }

    func remove(_ completedRequest: LocalPrivacyPurgeRequest) throws {
        var requests = try load()
        guard requests[completedRequest.ownerUserID] == completedRequest else {
            // A stronger request was queued while this idempotent deletion was
            // in flight. Leave it durable for the next drain.
            return
        }
        requests.removeValue(forKey: completedRequest.ownerUserID)
        try save(requests)
    }

    private func load() throws -> [UUID: LocalPrivacyPurgeRequest] {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return [:]
        }
        let requests = try decoder.decode([LocalPrivacyPurgeRequest].self, from: data)
        return Dictionary(uniqueKeysWithValues: requests.map { ($0.ownerUserID, $0) })
    }

    private func save(_ requests: [UUID: LocalPrivacyPurgeRequest]) throws {
        if requests.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        let orderedRequests = requests.values.sorted {
            $0.ownerUserID.uuidString < $1.ownerUserID.uuidString
        }
        defaults.set(try encoder.encode(orderedRequests), forKey: Self.storageKey)
    }
}

private extension LocalPrivacyPurgeScope {
    nonisolated func merging(_ other: LocalPrivacyPurgeScope) -> LocalPrivacyPurgeScope {
        switch (self, other) {
        case (.departingUser, _), (_, .departingUser):
            return .departingUser
        case let (
            .relationshipContentPurged(clearAccessSnapshot: lhs),
            .relationshipContentPurged(clearAccessSnapshot: rhs)
        ):
            return .relationshipContentPurged(clearAccessSnapshot: lhs || rhs)
        case let (.relationshipContentPurged(clearAccessSnapshot), _),
             let (_, .relationshipContentPurged(clearAccessSnapshot)):
            return .relationshipContentPurged(clearAccessSnapshot: clearAccessSnapshot)
        case (.relationshipAccessHidden, .relationshipAccessHidden):
            return .relationshipAccessHidden
        }
    }
}
