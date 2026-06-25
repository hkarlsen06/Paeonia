import Foundation

/// A device-scoped client operation that makes the widget reserve / finalize /
/// submit calls idempotent and ordered, mirroring the pairing and media
/// upload client-operation pattern.
typealias WidgetCanvasClientOperation = SyncClientOperation

nonisolated protocol WidgetCanvasClientOperationProviding: Sendable {
    func makeOperation() async -> WidgetCanvasClientOperation
}

/// Serializes monotonic `clientSequence` allocation through actor isolation so a
/// device never reuses a sequence value across concurrent uploads.
actor WidgetCanvasClientOperationFactory: WidgetCanvasClientOperationProviding {
    nonisolated static let shared = WidgetCanvasClientOperationFactory()

    func makeOperation() async -> WidgetCanvasClientOperation {
        await MainActor.run {
            SyncClientOperationFactory.shared.makeOperation()
        }
    }
}
