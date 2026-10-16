import Foundation
import Testing
@testable import PaeoniaApp

private enum HeartsFixture {
    static let me = UUID()
    static let couple = UUID()
    static let otherCouple = UUID()

    static func server(total: Int, seen: Int, couple: UUID = couple) -> RemoteHeartsState {
        RemoteHeartsState(coupleID: couple, receivedTotal: total, receivedSeenTotal: seen)
    }
}

extension RemoteHeartsState {
    fileprivate init(coupleID: UUID, receivedTotal: Int, receivedSeenTotal: Int) {
        let json = """
        {"couple_id":"\(coupleID.uuidString)","received_total":\(receivedTotal),\
        "received_seen_total":\(receivedSeenTotal)}
        """
        // swiftlint:disable:next force_try
        self = try! JSONDecoder().decode(RemoteHeartsState.self, from: Data(json.utf8))
    }
}

struct HeartsTapBatcherTests {
    @Test func noTapsMakeNoBatch() {
        var batcher = HeartsTapBatcher()
        #expect(batcher.takeBatches().isEmpty)
        #expect(!batcher.hasPendingTaps)
    }

    @Test func tapsBeforeTheQuietPeriodEndsGoOutAsOneBatch() {
        var batcher = HeartsTapBatcher()
        for _ in 0..<7 { batcher.tap() }
        #expect(batcher.hasPendingTaps)
        #expect(batcher.takeBatches() == [7])
        #expect(!batcher.hasPendingTaps)
        #expect(batcher.takeBatches().isEmpty)
    }

    @Test func aBatchHoldsAtMostWhatTheServerAcceptsPerCall() {
        var batcher = HeartsTapBatcher()
        for _ in 0..<207 { batcher.tap() }
        #expect(batcher.takeBatches() == [100, 100, 7])
        for _ in 0..<100 { batcher.tap() }
        #expect(batcher.takeBatches() == [100])
    }

    @Test func theQuietPeriodIsOneAndAHalfSeconds() {
        #expect(HeartsTapBatcher.quietPeriod == .milliseconds(1_500))
    }
}

struct HeartsInboxTests {
    @Test func unseenHeartsAreWhatThePartnerSentMinusWhatWasShown() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 14, seen: 3))
        #expect(inbox.unseenCount == 11)
    }

    @Test func markShownReturnsTheBurstAndTheTotalForTheServer() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 14, seen: 0))
        #expect(inbox.pendingBurst == HeartsShown(count: 14, total: 14))
        inbox.markShown(upTo: 14)
        #expect(inbox.unseenCount == 0)
        #expect(inbox.pendingBurst == nil)
    }

    @Test func aServerAnswerThatIsBehindDoesNotBringBackShownHearts() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 14, seen: 0))
        inbox.markShown(upTo: 14)
        // The mark is still on its way to the server.
        inbox.apply(HeartsFixture.server(total: 14, seen: 0))
        #expect(inbox.unseenCount == 0)
    }

    @Test func heartsThatArriveWhileABurstPlaysStayUnseen() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 14, seen: 0))
        inbox.markShown(upTo: 14)
        inbox.apply(HeartsFixture.server(total: 17, seen: 14))
        #expect(inbox.unseenCount == 3)
        #expect(inbox.pendingBurst == HeartsShown(count: 3, total: 17))
    }

    @Test func totalsNeverGoDownFromALateAnswer() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 20, seen: 5))
        inbox.apply(HeartsFixture.server(total: 20, seen: 2))
        #expect(inbox.seenTotal == 5)
        #expect(inbox.receivedTotal == 20)
    }

    @Test func aNewCoupleStartsOverFromTheServersNumbers() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 50, seen: 50))
        inbox.apply(HeartsFixture.server(total: 2, seen: 0, couple: HeartsFixture.otherCouple))
        #expect(inbox.unseenCount == 2)
    }

    @Test func totalsThatWentDownOnTheServerStartOver() {
        var inbox = HeartsInbox()
        inbox.apply(HeartsFixture.server(total: 50, seen: 50))
        inbox.apply(HeartsFixture.server(total: 4, seen: 1))
        #expect(inbox.receivedTotal == 4)
        #expect(inbox.unseenCount == 3)
    }

    @Test func aBigBurstFliesAtMostTwelveHearts() {
        #expect(HeartsBurst(count: 1).flyingCount == 1)
        #expect(HeartsBurst(count: 12).flyingCount == 12)
        #expect(HeartsBurst(count: 100).flyingCount == 12)
    }
}

struct HeartsCacheTests {
    private func makeCache() -> FileHeartsCache {
        FileHeartsCache(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("hearts-cache-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func shownHeartsStayShownAfterARelaunch() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hearts-cache-\(UUID().uuidString)", isDirectory: true)
        let first = FileHeartsCache(directoryURL: directory)
        await first.save(HeartsFixture.server(total: 9, seen: 0), ownerUserID: HeartsFixture.me)
        await first.markShown(upTo: 9, ownerUserID: HeartsFixture.me)

        let relaunched = FileHeartsCache(directoryURL: directory)
        #expect(await relaunched.inbox(ownerUserID: HeartsFixture.me).unseenCount == 0)
    }

    @Test func anotherAccountOnThePhoneReadsNothing() async {
        let cache = makeCache()
        await cache.save(HeartsFixture.server(total: 9, seen: 0), ownerUserID: HeartsFixture.me)
        #expect(await cache.inbox(ownerUserID: UUID()) == HeartsInbox())
    }

    @Test func clearAllForgetsEverything() async {
        let cache = makeCache()
        await cache.save(HeartsFixture.server(total: 9, seen: 0), ownerUserID: HeartsFixture.me)
        await cache.clearAll()
        #expect(await cache.inbox(ownerUserID: HeartsFixture.me) == HeartsInbox())
    }
}

/// Holds a burst's line on screen until a test lets it go.
private final class LineGate: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func hold() async throws {
        for await _ in stream {
            return
        }
        try Task.checkCancellation()
    }

    func release() {
        continuation.yield()
    }
}

@MainActor
private final class AnnouncementRecorder {
    private(set) var lines: [String] = []

    func record(_ line: String) {
        lines.append(line)
    }
}

@MainActor
struct HeartsViewModelTests {
    private struct Rig {
        let viewModel: HeartsViewModel
        let cache: FileHeartsCache
        let store: InMemoryPendingSyncOperationRepository
        let announcements: AnnouncementRecorder
        let syncCount: SyncCounter
        let lineGate: LineGate
    }

    @MainActor
    final class SyncCounter {
        var sends = 0
    }

    private func makeRig() -> Rig {
        let cache = FileHeartsCache(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("hearts-vm-\(UUID().uuidString)", isDirectory: true))
        let store = InMemoryPendingSyncOperationRepository()
        let announcements = AnnouncementRecorder()
        let syncCount = SyncCounter()
        let lineGate = LineGate()
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        let viewModel = HeartsViewModel(
            cache: cache,
            pendingOperationStore: store,
            operationProvider: SyncClientOperationFactory(defaults: defaults),
            sleep: { duration in
                if duration == HeartsTapBatcher.quietPeriod {
                    // A short real wait that a newer tap cancels, like the real quiet period.
                    try await Task.sleep(for: .milliseconds(20))
                } else {
                    try await lineGate.hold()
                }
            },
            announceBurst: { announcements.record($0) }
        )
        viewModel.configure(ownerUserID: HeartsFixture.me, partnerName: "Robin")
        viewModel.setSyncAfterLocalChange { syncCount.sends += 1 }
        return Rig(
            viewModel: viewModel,
            cache: cache,
            store: store,
            announcements: announcements,
            syncCount: syncCount,
            lineGate: lineGate
        )
    }

    private func sendCounts(in rig: Rig) async throws -> [Int] {
        let operations = try await rig.store.inFlightOperations(ownerUserID: HeartsFixture.me, kind: .sendHearts)
        return try operations.map {
            try JSONDecoder().decode(HeartsSendPayload.self, from: #require($0.requestData)).count
        }
    }

    private func seenTotals(in rig: Rig) async throws -> [Int] {
        let operations = try await rig.store.inFlightOperations(ownerUserID: HeartsFixture.me, kind: .markHeartsSeen)
        return try operations.map {
            try JSONDecoder().decode(HeartsSeenPayload.self, from: #require($0.requestData)).seenTotal
        }
    }

    @Test func tapsBeforeTheQuietPeriodEndsBecomeOneWrite() async throws {
        let rig = makeRig()
        for _ in 0..<5 { rig.viewModel.tap() }
        #expect(try await sendCounts(in: rig).isEmpty)

        await rig.viewModel.flushTask?.value
        #expect(try await sendCounts(in: rig) == [5])
        #expect(await waitUntil { rig.syncCount.sends == 1 })
    }

    @Test func moreThanAHundredTapsBecomeSeveralWrites() async throws {
        let rig = makeRig()
        for _ in 0..<105 { rig.viewModel.tap() }
        await rig.viewModel.flushTaps()
        #expect(try await sendCounts(in: rig) == [100, 5])
    }

    @Test func leavingHomeSendsTheWaitingTapsAtOnce() async throws {
        let rig = makeRig()
        rig.viewModel.setHomeVisible(true)
        rig.viewModel.tap()
        rig.viewModel.tap()
        rig.viewModel.setHomeVisible(false)

        let sent = await waitUntil { rig.syncCount.sends > 0 }
        #expect(sent)
        #expect(try await sendCounts(in: rig) == [2])
    }

    @Test func noTapIsSentWithoutASignedInPerson() async throws {
        let rig = makeRig()
        rig.viewModel.configure(ownerUserID: nil, partnerName: "Robin")
        rig.viewModel.tap()
        await rig.viewModel.flushTaps()
        #expect(try await sendCounts(in: rig).isEmpty)
    }

    @Test func unseenHeartsPlayOnceWhenHomeIsInFront() async throws {
        let rig = makeRig()
        await rig.cache.save(HeartsFixture.server(total: 14, seen: 0), ownerUserID: HeartsFixture.me)
        rig.viewModel.setHomeVisible(true)
        rig.viewModel.setScreenReady(true)

        let played = await waitUntil { rig.viewModel.incomingBurst != nil }
        #expect(played)
        #expect(rig.viewModel.incomingBurst?.count == 14)
        #expect(rig.viewModel.incomingBurst?.flyingCount == 12)
        #expect(rig.viewModel.incomingLine?.contains("Robin") == true)
        #expect(rig.announcements.lines.count == 1)
        // The burst shows before the seen write is queued, so wait for the write.
        var totals = try await seenTotals(in: rig)
        for _ in 0..<200 where totals.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
            totals = try await seenTotals(in: rig)
        }
        #expect(totals == [14])

        // Nothing is left to play, so another look does not play them again.
        await rig.viewModel.playIfNeeded()
        #expect(rig.announcements.lines.count == 1)
        #expect(await rig.cache.inbox(ownerUserID: HeartsFixture.me).unseenCount == 0)
    }

    @Test func heartsWaitWhileHomeIsNotInFront() async throws {
        let rig = makeRig()
        await rig.cache.save(HeartsFixture.server(total: 3, seen: 0), ownerUserID: HeartsFixture.me)
        rig.viewModel.setScreenReady(true)
        await rig.viewModel.playIfNeeded()
        #expect(rig.viewModel.incomingBurst == nil)
        #expect(await rig.cache.inbox(ownerUserID: HeartsFixture.me).unseenCount == 3)

        rig.viewModel.setHomeVisible(true)
        let played = await waitUntil { rig.viewModel.incomingBurst != nil }
        #expect(played)
        #expect(rig.viewModel.incomingBurst?.count == 3)
    }

    @Test func markingAnEarlierTotalLeavesLaterHeartsUnseen() async {
        let cache = FileHeartsCache(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("hearts-cache-\(UUID().uuidString)", isDirectory: true))
        await cache.save(HeartsFixture.server(total: 17, seen: 0), ownerUserID: HeartsFixture.me)
        await cache.markShown(upTo: 14, ownerUserID: HeartsFixture.me)
        #expect(await cache.inbox(ownerUserID: HeartsFixture.me).unseenCount == 3)
    }

    @Test func heartsThatFindHomeHiddenAfterTheReadStayUnseen() async throws {
        let rig = makeRig()
        await rig.cache.save(HeartsFixture.server(total: 5, seen: 0), ownerUserID: HeartsFixture.me)
        rig.viewModel.setHomeVisible(true)
        rig.viewModel.setScreenReady(true)
        // Home hides in the same turn, before the read of the cache returns.
        let play = Task { await rig.viewModel.playIfNeeded() }
        rig.viewModel.setHomeVisible(false)
        await play.value
        await Task.yield()

        #expect(rig.viewModel.incomingBurst == nil)
        #expect(rig.announcements.lines.isEmpty)
        #expect(try await seenTotals(in: rig).isEmpty)
        #expect(await rig.cache.inbox(ownerUserID: HeartsFixture.me).unseenCount == 5)
    }

    @Test func heartsWaitForTheLaunchIntroAndForTheAppToBeInFront() async throws {
        let rig = makeRig()
        await rig.cache.save(HeartsFixture.server(total: 3, seen: 0), ownerUserID: HeartsFixture.me)
        rig.viewModel.setHomeVisible(true)
        await rig.viewModel.playIfNeeded()
        #expect(rig.viewModel.incomingBurst == nil)
    }

    @Test func aHeartThatArrivesDuringABurstWaitsForTheNextOne() async throws {
        let rig = makeRig()
        await rig.cache.save(HeartsFixture.server(total: 14, seen: 0), ownerUserID: HeartsFixture.me)
        rig.viewModel.setHomeVisible(true)
        rig.viewModel.setScreenReady(true)
        let played = await waitUntil { rig.viewModel.incomingBurst != nil }
        #expect(played)

        await rig.cache.save(HeartsFixture.server(total: 17, seen: 0), ownerUserID: HeartsFixture.me)
        // The first mark told the server 14, so the 3 new hearts are still unseen.
        #expect(try await seenTotals(in: rig) == [14])
        #expect(await rig.cache.inbox(ownerUserID: HeartsFixture.me).unseenCount == 3)

        // When the first burst ends, the 3 play as a burst of their own.
        rig.lineGate.release()
        let second = await waitUntil { rig.viewModel.incomingBurst?.count == 3 }
        #expect(second)
        #expect(try await seenTotals(in: rig) == [14, 17])
    }
}

struct HeartsPendingOperationHandlerTests {
    // The protocol is async, and this stand-in answers at once.
    // swiftlint:disable async_without_await
    private final class StubGateway: HeartsGateway, @unchecked Sendable {
        var error: PaeoniaConvexError?
        private(set) var sentCounts: [Int] = []
        private(set) var seenTotals: [Int] = []

        func sendHearts(count: Int, operation _: SyncClientOperation) async throws {
            if let error { throw error }
            sentCounts.append(count)
        }

        func markHeartsSeen(seenTotal: Int) async throws {
            if let error { throw error }
            seenTotals.append(seenTotal)
        }
    }
    // swiftlint:enable async_without_await

    private func context() -> SyncContext {
        SyncContext(
            session: SyncSession(userID: HeartsFixture.me, activeCoupleID: HeartsFixture.couple),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
    }

    @Test func aSendReachesTheGateway() async throws {
        let gateway = StubGateway()
        let handler = SendHeartsPendingOperationHandler(gateway: gateway)
        let operation = try snapshot(.sendHearts, HeartsSendPayload(count: 9), owner: HeartsFixture.me)
        #expect(try await handler.send(operation, context: context()) == .succeeded)
        #expect(gateway.sentCounts == [9])
    }

    @Test func aSeenMarkReachesTheGateway() async throws {
        let gateway = StubGateway()
        let handler = MarkHeartsSeenPendingOperationHandler(gateway: gateway)
        let operation = try snapshot(.markHeartsSeen, HeartsSeenPayload(seenTotal: 17), owner: HeartsFixture.me)
        #expect(try await handler.send(operation, context: context()) == .succeeded)
        #expect(gateway.seenTotals == [17])
    }

    @Test func aRefusalThatCannotChangeDropsTheWrite() async throws {
        let gateway = StubGateway()
        let handler = SendHeartsPendingOperationHandler(gateway: gateway)
        let operation = try snapshot(.sendHearts, HeartsSendPayload(count: 9), owner: HeartsFixture.me)

        gateway.error = .server(code: "23514", message: "hearts count must be between 1 and 100")
        guard case .terminalFailure = try await handler.send(operation, context: context()) else {
            Issue.record("expected a terminal failure")
            return
        }
        gateway.error = .server(code: "42501", message: "an active partner is required to send hearts")
        guard case .terminalFailure = try await handler.send(operation, context: context()) else {
            Issue.record("expected a terminal failure")
            return
        }
    }

    @Test func tooManySendsAndSignInProblemsKeepTheWriteForLater() async throws {
        let gateway = StubGateway()
        let handler = SendHeartsPendingOperationHandler(gateway: gateway)
        let operation = try snapshot(.sendHearts, HeartsSendPayload(count: 9), owner: HeartsFixture.me)

        for error in [
            PaeoniaConvexError.server(code: "53300", message: "too many requests: heartsSend"),
            .server(code: "42501", message: "authenticated user required"),
            .notAuthenticated,
        ] {
            gateway.error = error
            await #expect(throws: PaeoniaConvexError.self) {
                try await handler.send(operation, context: context())
            }
        }
    }
}
