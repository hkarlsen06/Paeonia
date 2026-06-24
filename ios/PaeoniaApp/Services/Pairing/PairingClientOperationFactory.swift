import Foundation

@MainActor
protocol PairingClientOperationProviding: AnyObject {
    func makeOperation() -> PairingClientOperation
}

@MainActor
final class PairingClientOperationFactory: PairingClientOperationProviding {
    static let shared = PairingClientOperationFactory()

    private enum DefaultsKey {
        static let clientID = "paeonia.pairing.clientID"
        static let clientSequence = "paeonia.pairing.clientSequence"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func makeOperation() -> PairingClientOperation {
        let clientID = resolvedClientID()
        let sequence = nextSequence()

        return PairingClientOperation(
            clientID: clientID,
            clientSequence: sequence
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
