import Foundation
import Testing
@testable import PaeoniaApp

extension MemoryDataLayerTests {
    /// The server counts Unicode code points, not characters. "👍🏽" is one character
    /// and two code points, so 80 of them fill the title exactly.
    @Test func updateMemoryRefusesATitleOverTheServersLimitAndQueuesNothing() async throws {
        let seeded = try await seededMemory()
        let fullTitle = String(repeating: "👍🏽", count: 80)
        #expect(fullTitle.unicodeScalars.count == MemoryDataService.titleCharacterLimit)

        await #expect(throws: MemoryDataServiceError.titleTooLong) {
            try await seeded.service.updateMemory(
                ownerUserID: seeded.ownerUserID,
                memoryID: seeded.memoryID,
                expectedRevision: seeded.revision,
                title: fullTitle + "a",
                memoryDate: "2026-06-30",
                operation: operation(id: "55555555-5555-5555-5555-555555555555", sequence: 2)
            )
        }
        #expect(try await seeded.queued(.updateMemory).isEmpty)

        let accepted = try await seeded.service.updateMemory(
            ownerUserID: seeded.ownerUserID,
            memoryID: seeded.memoryID,
            expectedRevision: seeded.revision,
            title: fullTitle,
            memoryDate: "2026-06-30",
            operation: operation(id: "66666666-6666-6666-6666-666666666666", sequence: 3)
        )
        #expect(accepted.snapshot.title == fullTitle)
        #expect(try await seeded.queued(.updateMemory).count == 1)
    }

    @Test func upsertMemoryNoteRefusesABodyOverTheServersLimitAndQueuesNothing() async throws {
        let seeded = try await seededMemory()

        await #expect(throws: MemoryDataServiceError.noteTooLong) {
            try await seeded.service.upsertMemoryNote(
                ownerUserID: seeded.ownerUserID,
                memoryID: seeded.memoryID,
                expectedRevision: nil,
                body: String(repeating: "a", count: MemoryDataService.noteCharacterLimit + 1),
                operation: operation(id: "55555555-5555-5555-5555-555555555555", sequence: 2)
            )
        }
        #expect(try await seeded.queued(.upsertMemoryNote).isEmpty)

        _ = try await seeded.service.upsertMemoryNote(
            ownerUserID: seeded.ownerUserID,
            memoryID: seeded.memoryID,
            expectedRevision: nil,
            body: String(repeating: "a", count: MemoryDataService.noteCharacterLimit),
            operation: operation(id: "66666666-6666-6666-6666-666666666666", sequence: 3)
        )
        #expect(try await seeded.queued(.upsertMemoryNote).count == 1)
    }

    @Test func shorteningTextNeverCutsACharacterInHalf() {
        #expect(MemoryDataService.prefix("ab👍🏽", fittingCodePoints: 3) == "ab")
        #expect(MemoryDataService.prefix("ab👍🏽", fittingCodePoints: 4) == "ab👍🏽")
        #expect(MemoryDataService.prefix("abc", fittingCodePoints: 5) == "abc")
    }
}
