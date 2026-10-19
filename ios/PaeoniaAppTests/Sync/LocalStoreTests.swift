import Foundation
import SwiftData
import Testing
@testable import PaeoniaApp

struct LocalStoreTests {
    @Test func createsPersistentStoreDirectoryBeforeOpeningStore() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = rootDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try PaeoniaLocalStore.createStoreDirectory(for: storeURL)

        var isDirectory: ObjCBool = false
        let directoryExists = FileManager.default.fileExists(
            atPath: storeURL.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        )
        #expect(directoryExists)
        #expect(isDirectory.boolValue)
    }
}
