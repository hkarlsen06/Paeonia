import Foundation
import Testing
@testable import PaeoniaApp

struct LocationPauseOptionTests {
    private let oslo = TimeZone(identifier: "Europe/Oslo") ?? .gmt

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oslo
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: iso))
    }

    @Test func untilMorningEndsAtEightOnTheNextMorning() throws {
        let evening = try date("2026-10-21T21:00:00+02:00")
        let end = LocationPauseOption.untilMorning.end(from: evening, calendar: calendar)
        #expect(end == (try date("2026-10-22T08:00:00+02:00")))
    }

    @Test func untilMorningFromThePreLightHoursEndsTheSameMorning() throws {
        let night = try date("2026-10-21T02:00:00+02:00")
        let end = LocationPauseOption.untilMorning.end(from: night, calendar: calendar)
        #expect(end == (try date("2026-10-21T08:00:00+02:00")))
    }

    @Test func untilMorningNeverEndsInLessThanAnHour() throws {
        let almostMorning = try date("2026-10-21T07:30:00+02:00")
        let end = LocationPauseOption.untilMorning.end(from: almostMorning, calendar: calendar)
        #expect(end == (try date("2026-10-22T08:00:00+02:00")))
    }

    @Test func untilMorningFollowsTheClockAcrossADaylightSavingChange() throws {
        // Norway moves its clocks back on 25 October 2026, so 08:00 is one hour later in UTC.
        let evening = try date("2026-10-24T23:00:00+02:00")
        let end = LocationPauseOption.untilMorning.end(from: evening, calendar: calendar)
        #expect(end == (try date("2026-10-25T08:00:00+01:00")))
    }

    @Test func hourChoicesAddWholeHours() throws {
        let now = try date("2026-10-21T21:00:00+02:00")
        #expect(LocationPauseOption.oneHour.end(from: now, calendar: calendar) == now.addingTimeInterval(3_600))
        #expect(LocationPauseOption.fourHours.end(from: now, calendar: calendar) == now.addingTimeInterval(14_400))
    }
}

struct LocationPauseSharingChoiceTests {
    private let ownerUserID = UUID()
    private let coupleID = UUID()
    private let now = Date(timeIntervalSince1970: 10_000)

    private func serverSnapshot(pausedUntil: Date?) -> LocationVisibilitySnapshot {
        LocationVisibilitySnapshot(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            viewerUserID: ownerUserID,
            partnerUserID: UUID(),
            visibilityState: pausedUntil == nil ? .notSharing : .viewerPaused,
            viewerSharingEnabled: true,
            partnerSharingEnabled: true,
            partnerLocation: nil,
            partnerLocationIsStale: false,
            updatedAt: now,
            refreshedAt: now,
            viewerPausedUntil: pausedUntil
        )
    }

    /// The feed can deliver the answer from before a pause while the pause waits to be sent.
    @Test func olderServerAnswerDoesNotEndAPauseThatIsStillSending() async throws {
        let store = InMemoryLocationVisibilityRepository()
        let end = now.addingTimeInterval(3_600)
        try await store.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: end,
            updatedAt: now
        )

        try await store.saveRemote(serverSnapshot(pausedUntil: nil), preservingLocalSharingChoiceIf: true)

        let stored = try #require(try await store.load(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(stored.viewerPausedUntil == end)
        #expect(stored.visibilityState == .viewerPaused)
    }

    /// Resume is a choice too. A pause the server still reports must not bring the pause back.
    @Test func olderServerAnswerDoesNotRestartAPauseThatWasJustEnded() async throws {
        let store = InMemoryLocationVisibilityRepository()
        let end = now.addingTimeInterval(3_600)
        try await store.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: nil,
            updatedAt: now
        )

        try await store.saveRemote(serverSnapshot(pausedUntil: end), preservingLocalSharingChoiceIf: true)

        let stored = try #require(try await store.load(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(stored.viewerPausedUntil == nil)
        #expect(stored.viewerSharingEnabled)
    }

    @Test func confirmedPauseClearsTheUnconfirmedChoice() async throws {
        let store = InMemoryLocationVisibilityRepository()
        let end = now.addingTimeInterval(3_600)
        try await store.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: end,
            updatedAt: now
        )
        try await store.confirmViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            choice: ViewerSharingChoice(isEnabled: true, pausedUntil: end.addingTimeInterval(0.4)),
            updatedAt: now,
            otherChoicesPending: false
        )

        // With nothing pending, the server's answer is the truth again.
        try await store.saveRemote(serverSnapshot(pausedUntil: nil), preservingLocalSharingChoiceIf: false)
        let stored = try #require(try await store.load(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(stored.viewerPausedUntil == nil)
    }

    /// A pause saved offline can reach the server after its end. The server answers with no pause. The
    /// answer must still match the saved choice, apply, and release the live results.
    @Test func pauseSavedOfflineIsConfirmedEvenWhenTheServerAlreadyEndedIt() async throws {
        let store = InMemoryLocationVisibilityRepository()
        let end = now.addingTimeInterval(3_600)
        try await store.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: end,
            updatedAt: now
        )

        try await store.confirmViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            confirmation: ViewerSharingConfirmation(
                submitted: ViewerSharingChoice(isEnabled: true, pausedUntil: end),
                confirmed: ViewerSharingChoice(isEnabled: true, pausedUntil: nil)
            ),
            updatedAt: end.addingTimeInterval(60),
            otherChoicesPending: false
        )
        let confirmed = try #require(try await store.load(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(confirmed.viewerPausedUntil == nil)
        #expect(confirmed.visibilityState != .viewerPaused)

        // Nothing is pending any more, so a live answer without a pause is taken as it is.
        try await store.saveRemote(serverSnapshot(pausedUntil: nil), preservingLocalSharingChoiceIf: false)
        let live = try #require(try await store.load(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(live.visibilityState != .viewerPaused)
        #expect(live.viewerPausedUntil == nil)
    }

    @Test func confirmationOfAnOlderChoiceLeavesTheNewerOneAlone() async throws {
        let store = InMemoryLocationVisibilityRepository()
        let older = now.addingTimeInterval(1_800)
        let newer = now.addingTimeInterval(7_200)
        try await store.setViewerSharingEnabled(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            isEnabled: true,
            pausedUntil: newer,
            updatedAt: now
        )

        try await store.confirmViewerSharing(
            ownerUserID: ownerUserID,
            coupleID: coupleID,
            confirmation: ViewerSharingConfirmation(ViewerSharingChoice(isEnabled: true, pausedUntil: older)),
            updatedAt: now,
            otherChoicesPending: false
        )
        let stored = try #require(try await store.load(ownerUserID: ownerUserID, coupleID: coupleID))
        #expect(stored.viewerPausedUntil == newer)
    }

    @Test func mapShowsThePauseUntilItsTimeAndThenStopsShowingIt() {
        let end = now.addingTimeInterval(3_600)
        let snapshot = serverSnapshot(pausedUntil: end)

        let during = LocationMapViewModel.resolveMapState(visibility: snapshot, ownLocation: nil, now: now)
        #expect(during == .sharingPaused(until: end))
        let after = LocationMapViewModel.resolveMapState(
            visibility: snapshot,
            ownLocation: nil,
            now: end.addingTimeInterval(1)
        )
        #expect(after != .sharingPaused(until: end))
    }
}
