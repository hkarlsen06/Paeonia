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

    @Test func localDateStringIsZeroPadded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = try #require(calendar.date(from: DateComponents(year: 2_026, month: 1, day: 5)))

        #expect(MemoryTimeline.localDateString(for: date, timeZone: .gmt) == "2026-01-05")
    }

    /// Opening the edit form and saving without touching the date must keep the date.
    /// The form used to seed its picker with UTC midnight, which is the previous evening
    /// west of UTC, so every save there moved the memory back a day.
    @Test(arguments: ["America/Los_Angeles", "Pacific/Honolulu", "Europe/Oslo", "Pacific/Kiritimati"])
    func pickerDateRoundTripsToTheSameDay(zoneID: String) throws {
        let zone = try #require(TimeZone(identifier: zoneID))

        for stored in ["2026-01-01", "2026-03-08", "2026-03-29", "2026-10-25", "2026-11-01", "2026-12-31"] {
            let pickerDate = try #require(MemoryTimeline.pickerDate(forLocalDate: stored, timeZone: zone))
            #expect(MemoryTimeline.localDateString(for: pickerDate, timeZone: zone) == stored)
        }
    }

    @Test func localDateStringIsGregorianWhateverTheDeviceCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = .gmt
        // Year 2569 in the Buddhist calendar is 2026 in the Gregorian one.
        let date = try #require(buddhist.date(from: DateComponents(year: 2_569, month: 6, day: 30, hour: 12)))

        #expect(MemoryTimeline.localDateString(for: date, timeZone: .gmt) == "2026-06-30")
    }

    @Test func monthsFoldDaysIntoNewestFirstSections() throws {
        let days = MemoryTimeline.grouped([
            makeRecord(date: "2026-06-02", createdAt: 100),
            makeRecord(date: "2026-07-15", createdAt: 300),
            makeRecord(date: "2026-06-28", createdAt: 200),
            makeRecord(date: "2025-12-31", createdAt: 50)
        ])

        let months = MemoryTimeline.months(days)

        #expect(months.map(\.id) == ["2026-07", "2026-06", "2025-12"])
        #expect(months[1].memories.map(\.snapshot.memoryDate) == ["2026-06-28", "2026-06-02"])
        #expect(months[0].monthStartUTC == MemoryTimeline.parseLocalDate("2026-07-01"))
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
                place: nil,
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
