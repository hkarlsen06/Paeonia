import Foundation

nonisolated struct SyncClientOperation: Codable, Equatable, Sendable {
    let id: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        id: UUID = UUID(),
        clientID: UUID,
        clientSequence: Int64,
        localCreatedAt: Date = Date()
    ) {
        self.id = id
        self.clientID = clientID
        self.clientSequence = clientSequence
        self.localCreatedAt = localCreatedAt
    }
}

@MainActor
protocol SyncClientOperationProviding: AnyObject {
    func makeOperation() -> SyncClientOperation
}

@MainActor
final class SyncClientOperationFactory: SyncClientOperationProviding {
    static let shared = SyncClientOperationFactory()

    private enum DefaultsKey {
        static let clientID = "paeonia.sync.clientID"
        static let clientSequence = "paeonia.sync.clientSequence"
        static let legacyPairingClientID = "paeonia.pairing.clientID"
        static let legacyPairingClientSequence = "paeonia.pairing.clientSequence"
        static let legacyAuthClientID = "paeonia.auth.clientID"
        static let legacyAuthClientSequence = "paeonia.auth.clientSequence"
        static let legacyWidgetClientID = "paeonia.widgetCanvas.clientID"
        static let legacyWidgetClientSequence = "paeonia.widgetCanvas.clientSequence"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func makeOperation() -> SyncClientOperation {
        SyncClientOperation(
            clientID: resolvedClientID(),
            clientSequence: nextSequence()
        )
    }

    private func resolvedClientID() -> UUID {
        if let storedID = uuid(forKey: DefaultsKey.clientID) {
            return storedID
        }

        if let legacyID = firstLegacyClientID() {
            defaults.set(legacyID.uuidString, forKey: DefaultsKey.clientID)
            return legacyID
        }

        let clientID = UUID()
        defaults.set(clientID.uuidString, forKey: DefaultsKey.clientID)
        return clientID
    }

    private func nextSequence() -> Int64 {
        let currentValue = max(
            int64(forKey: DefaultsKey.clientSequence) ?? 0,
            legacyClientSequence()
        )
        let nextValue = max(currentValue + 1, 1)
        defaults.set(nextValue, forKey: DefaultsKey.clientSequence)
        return nextValue
    }

    private func uuid(forKey key: String) -> UUID? {
        guard let storedValue = defaults.string(forKey: key) else {
            return nil
        }

        return UUID(uuidString: storedValue)
    }

    private func firstLegacyClientID() -> UUID? {
        [
            DefaultsKey.legacyPairingClientID,
            DefaultsKey.legacyAuthClientID,
            DefaultsKey.legacyWidgetClientID
        ]
        .lazy
        .compactMap { self.uuid(forKey: $0) }
        .first
    }

    private func legacyClientSequence() -> Int64 {
        [
            DefaultsKey.legacyPairingClientSequence,
            DefaultsKey.legacyAuthClientSequence,
            DefaultsKey.legacyWidgetClientSequence
        ]
        .compactMap { self.int64(forKey: $0) }
        .max() ?? 0
    }

    private func int64(forKey key: String) -> Int64? {
        guard let storedValue = defaults.object(forKey: key) as? NSNumber else {
            return nil
        }

        return storedValue.int64Value
    }
}
