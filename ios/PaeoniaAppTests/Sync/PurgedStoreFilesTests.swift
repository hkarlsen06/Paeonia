import Foundation
import Testing
@testable import PaeoniaApp

/// Sign-out, account deletion and leaving the relationship delete the couple's rows. Their
/// text must not stay readable in the store file or its write-ahead log afterwards.
struct PurgedStoreFilesTests {
    static let scopes: [LocalPrivacyPurgeScope] = [
        .departingUser,
        .relationshipContentPurged(clearAccessSnapshot: true),
        .relationshipContentPurged(clearAccessSnapshot: false)
    ]

    @Test(arguments: scopes)
    func aPurgeLeavesNoDeletedTextInTheStoreFiles(scope: LocalPrivacyPurgeScope) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurgedStoreFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PaeoniaLocalStore(url: directory.appendingPathComponent("default.store"))
        let memories = SwiftDataMemoryRecordRepository(container: store.container, mediaCache: nil)
        let (owner, couple) = (UUID(), UUID())
        let marker = "harbour-note-\(UUID().uuidString)"
        try await memories.saveRemote(
            [.fixture(ownerUserID: owner, memoryID: UUID(), coupleID: couple, title: marker, syncUpdatedAt: .now)],
            ownerUserID: owner,
            mergePolicy: .preserveLocalChanges
        )
        try #require(Self.files(in: directory, contain: marker))

        let records = SwiftDataLocalPrivacyRecordStore(container: store.container)
        switch scope {
        case .departingUser:
            try await records.purgeDepartingUser(ownerUserID: owner)
        case .relationshipAccessHidden:
            try await records.hideRelationshipAccess(ownerUserID: owner)
        case let .relationshipContentPurged(clearAccessSnapshot):
            try await records.purgeRelationshipContent(ownerUserID: owner, clearAccessSnapshot: clearAccessSnapshot)
        }

        #expect(!Self.files(in: directory, contain: marker))
        // The store keeps working, so the next sign-in can save again.
        try await memories.saveRemote(
            [.fixture(ownerUserID: owner, memoryID: UUID(), coupleID: couple, title: "Ferry", syncUpdatedAt: .now)],
            ownerUserID: owner,
            mergePolicy: .preserveLocalChanges
        )
        #expect(try await memories.load(ownerUserID: owner).map(\.snapshot.title) == ["Ferry"])
    }

    private static func files(in directory: URL, contain marker: String) -> Bool {
        let needle = Data(marker.utf8)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            if let data = try? Data(contentsOf: file), data.contains(needle) {
                return true
            }
        }
        return false
    }
}
