import Foundation
import Testing
@testable import PaeoniaApp

struct MemoryTimelineTests {
    @Test func groupsByDayNewestFirst() throws {
        let records = [
            makeRecord(date: "2026-06-28", createdAt: 100),
            makeRecord(date: "2026-06-30", createdAt: 200),
            makeRecord(date: "2026-06-29", createdAt: 150)
        ]

        let days = MemoryTimeline.grouped(records)

        #expect(days.map(\.localDate) == ["2026-06-30", "2026-06-29", "2026-06-28"])
    }

    @Test func ordersWithinDayNewestCreatedFirst() throws {
        let older = makeRecord(date: "2026-06-30", createdAt: 100)
        let newer = makeRecord(date: "2026-06-30", createdAt: 300)
        let middle = makeRecord(date: "2026-06-30", createdAt: 200)

        let days = MemoryTimeline.grouped([older, newer, middle])

        let day = try #require(days.first)
        #expect(day.memories.map(\.snapshot.createdAt) == [
            Date(timeIntervalSince1970: 300),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 100)
        ])
    }

    @Test func excludesHiddenDeletedAndPendingDeleteMemories() throws {
        let visible = makeRecord(date: "2026-06-30", createdAt: 100)
        let hidden = makeRecord(date: "2026-06-30", createdAt: 110, moderationStatus: .hidden)
        let deleted = makeRecord(date: "2026-06-30", createdAt: 120, deletedAt: Date(timeIntervalSince1970: 130))
        let pendingDelete = makeRecord(date: "2026-06-30", createdAt: 140, syncStatus: .pendingDelete)

        let days = MemoryTimeline.grouped([visible, hidden, deleted, pendingDelete])

        let memories = days.flatMap(\.memories)
        #expect(memories.count == 1)
        #expect(memories.first?.snapshot.memoryID == visible.snapshot.memoryID)
    }

    @Test func dayStartIsMidnightUTCOfLocalDate() throws {
        let days = MemoryTimeline.grouped([makeRecord(date: "2026-06-30", createdAt: 100)])
        let expected = MemoryTimeline.parseLocalDate("2026-06-30")
        #expect(days.first?.dayStartUTC == expected)
    }

    @Test func parseLocalDateRejectsMalformedStrings() {
        #expect(MemoryTimeline.parseLocalDate("not-a-date") == nil)
        #expect(MemoryTimeline.parseLocalDate("2026-06") == nil)
        #expect(MemoryTimeline.parseLocalDate("2026-06-30") != nil)
    }

    @Test func currentLocalDateStringIsZeroPadded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = try #require(calendar.date(from: DateComponents(year: 2_026, month: 1, day: 5)))

        #expect(MemoryTimeline.currentLocalDateString(now: date, calendar: calendar) == "2026-01-05")
    }

    // MARK: - Fixtures

    private func makeRecord(
        date: String,
        createdAt: TimeInterval,
        syncStatus: SyncRecordStatus = .clean,
        moderationStatus: MemoryModerationStatus = .visible,
        deletedAt: Date? = nil
    ) -> MemoryRecord {
        let created = Date(timeIntervalSince1970: createdAt)
        return MemoryRecord(
            snapshot: MemorySnapshot(
                ownerUserID: UUID(),
                memoryID: UUID(),
                coupleID: UUID(),
                title: "Memory",
                memoryDate: date,
                createdByUserID: UUID(),
                lastEditedByUserID: UUID(),
                revision: 1,
                moderationStatus: moderationStatus,
                deletedAt: deletedAt,
                createdAt: created,
                updatedAt: created,
                syncUpdatedAt: created,
                ownNote: nil,
                partnerNote: nil,
                visibleMemoryMediaIDs: [],
                visibleMediaAssetIDs: [],
                media: [],
                threadID: nil
            ),
            syncStatus: syncStatus,
            localUpdatedAt: created
        )
    }
}
