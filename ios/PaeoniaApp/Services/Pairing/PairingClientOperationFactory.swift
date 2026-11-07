import Foundation

protocol PairingClientOperationProviding: AnyObject {
    func makeOperation() -> PairingClientOperation
}

final class PairingClientOperationFactory: PairingClientOperationProviding {
    static let shared = PairingClientOperationFactory()

    private let syncOperationProvider: any SyncClientOperationProviding

    init(syncOperationProvider: (any SyncClientOperationProviding)? = nil) {
        self.syncOperationProvider = syncOperationProvider ?? SyncClientOperationFactory.shared
    }

    func makeOperation() -> PairingClientOperation {
        syncOperationProvider.makeOperation()
    }
}
