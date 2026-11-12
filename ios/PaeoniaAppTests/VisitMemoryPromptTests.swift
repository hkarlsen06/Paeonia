import Foundation
import Testing
@testable import PaeoniaApp

/// When the Us tab asks for photos after a visit, and what it asks.
struct VisitMemoryPromptTests {
    let viewer = UUID()
    let partner = UUID()
    let visit = Visit(id: UUID(), startDate: "2026-10-01", endDate: "2026-10-05")

    private func day(_ raw: String) throws -> LockScreenCalendarDate {
        try #require(LockScreenCalendarDate(raw))
    }

    private func prompt(
        _ visit: Visit? = nil,
        memories: [MemorySnapshot] = [],
        on today: String
    ) throws -> VisitMemoryPrompt? {
        VisitMemoryPrompt(visit: visit ?? self.visit, memories: memories, viewerID: viewer, today: try day(today))
    }

    private func memory(photosBy owners: [UUID], visitID: UUID? = nil) -> MemorySnapshot {
        let now = Date()
        let media = owners.enumerated().map { index, owner in
            MemoryMediaSnapshot(
                memoryMediaID: UUID(), mediaAssetID: UUID(), ownerUserID: owner, sortOrder: index + 1, updatedAt: now
            )
        }
        return MemorySnapshot(
            ownerUserID: viewer, memoryID: UUID(), coupleID: UUID(), title: "Bergen", memoryDate: visit.startDate,
            place: nil, createdByUserID: partner, lastEditedByUserID: partner, revision: 1, moderationStatus: .visible,
            deletedAt: nil, createdAt: now, updatedAt: now, syncUpdatedAt: now, ownNote: nil, partnerNote: nil,
            visibleMemoryMediaIDs: media.map(\.memoryMediaID), visibleMediaAssetIDs: media.map(\.mediaAssetID),
            media: media, threadID: nil, visitID: visitID ?? visit.id
        )
    }

    @Test func nothingOnTheLastDayOfTheVisit() throws {
        #expect(try prompt(on: "2026-10-05") == nil)
    }

    @Test func theDayAfterItAsksToStartAMemory() throws {
        #expect(try prompt(on: "2026-10-06") == .startMemory(visit))
    }

    @Test func itStillAsksOnDay14AndIsGoneOnDay15() throws {
        #expect(try prompt(on: "2026-10-19") == .startMemory(visit))
        #expect(try prompt(on: "2026-10-20") == nil)
    }

    @Test func afterThePartnersPhotosItAsksForTheViewers() throws {
        let partnersMemory = memory(photosBy: [partner, partner])
        #expect(
            try prompt(memories: [partnersMemory], on: "2026-10-07")
                == .addYourPhotos(visit, memoryID: partnersMemory.memoryID, partnerAddedPhotos: true)
        )
    }

    @Test func aMemoryOfAnotherVisitStillAsksToStartOne() throws {
        let otherVisits = memory(photosBy: [viewer], visitID: UUID())
        #expect(try prompt(memories: [otherVisits], on: "2026-10-07") == .startMemory(visit))
    }

    @Test func nothingOnceTheViewerAddedPhotos() throws {
        #expect(try prompt(memories: [memory(photosBy: [partner, viewer])], on: "2026-10-07") == nil)
    }

    @Test func nothingOnceTheViewerHidIt() throws {
        var dismissed = visit
        dismissed.memoryPromptDismissed = true
        #expect(try prompt(dismissed, on: "2026-10-07") == nil)
    }

    @Test func theCardAsksAboutTheVisitThatEndedLast() throws {
        let earlier = Visit(id: UUID(), startDate: "2026-09-25", endDate: "2026-09-27")
        let current = VisitMemoryPrompt.current(
            visits: [visit, earlier], memories: [], viewerID: viewer, today: try day("2026-10-07")
        )
        #expect(current == .startMemory(visit))
    }

    @Test func thePartnersWaitingPhotosComeFirstAndALaterVisitStillAsksUnderThem() throws {
        let earlier = Visit(id: UUID(), startDate: "2026-09-25", endDate: "2026-09-27")
        let partners = memory(photosBy: [partner], visitID: earlier.id)
        let (visits, today) = ([visit, earlier], try day("2026-10-07"))

        let first = VisitMemoryPrompt.current(visits: visits, memories: [partners], viewerID: viewer, today: today)
        let waiting = VisitMemoryPrompt.current(
            visits: visits, memories: [partners], viewerID: viewer, today: today, waitingForViewer: true
        )
        let asking = VisitMemoryPrompt.current(
            visits: visits, memories: [partners], viewerID: viewer, today: today, waitingForViewer: false
        )

        let expected = VisitMemoryPrompt.addYourPhotos(earlier, memoryID: partners.memoryID, partnerAddedPhotos: true)
        #expect(first == expected)
        #expect(waiting == expected)
        #expect(asking == .startMemory(visit))
    }
}
