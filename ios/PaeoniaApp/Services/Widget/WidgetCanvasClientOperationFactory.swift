import Foundation

/// A device-scoped client operation that makes the widget reserve / finalize /
/// submit calls idempotent and ordered, mirroring the pairing and media
/// upload client-operation pattern.
nonisolated struct WidgetCanvasClientOperation: Sendable {
    let id: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
}

nonisolated protocol WidgetCanvasClientOperationProviding: Sendable {
    func makeOperation() async -> WidgetCanvasClientOperation
}

/// Serializes monotonic `clientSequence` allocation through actor isolation so a
/// device never reuses a sequence value across concurrent uploads.
actor WidgetCanvasClientOperationFactory: WidgetCanvasClientOperationProviding {
    nonisolated static let shared = WidgetCanvasClientOperationFactory()

    private enum DefaultsKey {
        static let clientID = "paeonia.widgetCanvas.clientID"
        static let clientSequence = "paeonia.widgetCanvas.clientSequence"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func makeOperation() -> WidgetCanvasClientOperation {
        WidgetCanvasClientOperation(
            id: UUID(),
            clientID: resolvedClientID(),
            clientSequence: nextSequence(),
            localCreatedAt: Date()
        )
    }

    private func resolvedClientID() -> UUID {
        if let storedValue = defaults.string(forKey: DefaultsKey.clientID),
           let storedID = UUID(uuidString: storedValue) {
            return storedID
        }

        let clientID = UUID()
        defaults.set(clientID.uuidString, forKey: DefaultsKey.clientID)
        return clientID
    }

    private func nextSequence() -> Int64 {
        let currentValue = Int64(defaults.integer(forKey: DefaultsKey.clientSequence))
        let nextValue = max(currentValue + 1, 1)
        defaults.set(nextValue, forKey: DefaultsKey.clientSequence)
        return nextValue
    }
}
