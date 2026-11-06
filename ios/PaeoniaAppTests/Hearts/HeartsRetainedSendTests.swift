import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct HeartsRetainedSendTests {
    @Test(arguments: [false, true])
    func failedBatchRetriesWithItsOriginalIdentityWithoutDuplicatingEarlierBatches(afterWriting: Bool) async throws {
        let owner = UUID()
        let store = RetainedContentPendingStore()
        await store.fail(at: 2, afterWriting: afterWriting)
        let model = HeartsViewModel(pendingOperationStore: store, sleep: { _ in
            try await Task.sleep(for: .seconds(60))
        })
        model.configure(ownerUserID: owner, partnerName: "Robin")
        for _ in 0..<105 { model.tap() }
        await model.flushTaps()
        #expect(model.hasUnqueuedHearts)
        model.tap()
        await model.flushTaps()
        #expect(!model.hasUnqueuedHearts)
        let operations = try await store.inFlightOperations(ownerUserID: owner, kind: .sendHearts)
        let counts = try operations.map {
            try JSONDecoder().decode(HeartsSendPayload.self, from: #require($0.requestData)).count
        }
        #expect(counts == [100, 5, 1])
        let attempts = await store.attempts
        #expect(attempts[1].operation.id == attempts[2].operation.id)
        model.configure(ownerUserID: nil, partnerName: "")
    }

    @Test func concurrentFlushAndNewTapsDoNotDuplicateAHeldBatch() async throws {
        let owner = UUID()
        let store = RetainedContentPendingStore()
        await store.holdNext()
        let model = HeartsViewModel(pendingOperationStore: store, sleep: { _ in
            try await Task.sleep(for: .seconds(60))
        })
        model.configure(ownerUserID: owner, partnerName: "Robin")
        model.tap()
        let first = Task { await model.flushTaps() }
        #expect(await waitUntil { await store.isHeld })
        model.tap()
        await model.flushTaps()
        await store.resume()
        await first.value
        let operations = try await store.inFlightOperations(ownerUserID: owner, kind: .sendHearts)
        #expect(operations.count == 2)
        #expect(Set(operations.map(\.operation.id)).count == 2)
        model.configure(ownerUserID: nil, partnerName: "")
    }
}
