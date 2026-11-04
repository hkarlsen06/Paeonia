import Foundation
@testable import PaeoniaApp

/// Stands in for Core Spotlight at the OS boundary: the entity ids it holds, and removals
/// that fail first, to script a retry.
actor FakeSpotlightIndex: SiriEntityIndexClearing {
    enum Failure: Error {
        case unavailable
    }

    private(set) var indexed: Set<String>
    private var failuresRemaining: Int

    init(indexed: Set<String> = [], failuresBeforeSuccess: Int = 0) {
        self.indexed = indexed
        failuresRemaining = failuresBeforeSuccess
    }

    func removeAllEntities() throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure.unavailable
        }
        indexed = []
    }
}
