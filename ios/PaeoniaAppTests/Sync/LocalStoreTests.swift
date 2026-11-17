import Foundation
import Testing
@testable import PaeoniaApp

struct LocalStoreTests {
    @Test func opensAStoreWhoseDirectoryDoesNotExistYet() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = rootDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        _ = try PaeoniaLocalStore(url: storeURL)

        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }
}
