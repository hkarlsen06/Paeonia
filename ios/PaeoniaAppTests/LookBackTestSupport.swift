import Foundation
import Testing
@testable import PaeoniaApp

// Fixtures shared by the look-back tests.

func lookBackID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}

enum LookBackIDs {
    static let user = lookBackID("aaaa0000-0000-0000-0000-000000000000")
    static let otherUser = lookBackID("bbbb0000-0000-0000-0000-000000000000")
    static let partner = lookBackID("cccc0000-0000-0000-0000-000000000000")
    static let couple = lookBackID("dddd0000-0000-0000-0000-000000000000")
    static let otherCouple = lookBackID("eeee0000-0000-0000-0000-000000000000")
    static let instance = lookBackID("11110000-0000-0000-0000-000000000000")
    static let memory = lookBackID("22220000-0000-0000-0000-000000000000")
    static let photo = lookBackID("33330000-0000-0000-0000-000000000000")
}

func lookBackMemoryItem(title: String = "Beach weekend", date: String = "2026-09-01") -> LookBackItem {
    LookBackItem(
        kind: .memory,
        contentDate: date,
        onThisDay: false,
        question: nil,
        drawing: nil,
        memory: .init(memoryID: LookBackIDs.memory, title: title, photoMediaAssetID: LookBackIDs.photo)
    )
}

func lookBackAnswer(
    _ userID: UUID,
    text: String? = nil,
    picked: UUID? = nil,
    photo: Bool = false,
    voice: Bool = false
) -> LookBackItem.Answer {
    .init(userID: userID, text: text, selectedUserID: picked, hasPhoto: photo, hasVoice: voice)
}

nonisolated final class MemoryLookBackCache: LookBackCaching, @unchecked Sendable {
    let lock = NSLock()
    var entries: [UUID: LookBackCacheEntry] = [:]
    var purges = 0

    func load(ownerUserID: UUID, coupleID: UUID?) -> LookBackCacheEntry? {
        lock.withLock {
            guard let entry = entries[ownerUserID] else { return nil }
            if let coupleID, let cached = entry.coupleID, cached != coupleID { return nil }
            return entry
        }
    }

    func save(_ entry: LookBackCacheEntry, ownerUserID: UUID) {
        lock.withLock { entries[ownerUserID] = entry }
    }

    func purgeCount() -> Int {
        lock.withLock { purges }
    }

    func save(_ entry: LookBackCacheEntry, ownerUserID: UUID, unlessPurgedSince purgeCount: Int) -> Bool {
        lock.withLock {
            guard purges == purgeCount else { return false }
            entries[ownerUserID] = entry
            return true
        }
    }

    func clearAll() {
        lock.withLock {
            purges += 1
            entries = [:]
        }
    }
}

func lookBackResponse(
    _ item: LookBackItem?,
    endsAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> LookBackResponse {
    LookBackResponse(item: item, endsAt: endsAt)
}

nonisolated final class StubLookBackService: LookBackServing, @unchecked Sendable {
    let lock = NSLock()
    var results: [Result<LookBackResponse, Error>]
    private(set) var requestTimes: [Date] = []

    init(_ results: [Result<LookBackResponse, Error>]) {
        self.results = results
    }

    // swiftlint:disable:next async_without_await
    func fetch(now: Date) async throws -> LookBackResponse {
        let next = lock.withLock { () -> Result<LookBackResponse, Error> in
            requestTimes.append(now)
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        return try next.get()
    }
}

/// Holds every read until the test finishes it, so a test controls the order they end in.
nonisolated final class GatedLookBackService: LookBackServing, @unchecked Sendable {
    let lock = NSLock()
    var waiting: [CheckedContinuation<LookBackResponse, Error>] = []
    var started = 0

    var startedCount: Int { lock.withLock { started } }

    func fetch(now: Date) async throws -> LookBackResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                started += 1
                waiting.append(continuation)
            }
        }
    }

    func finish(read index: Int, with response: LookBackResponse) {
        let continuation = lock.withLock { waiting[index] }
        continuation.resume(returning: response)
    }
}

/// Lets other tasks run until `condition` holds.
@MainActor
func lookBackWaitUntil(_ condition: () -> Bool) async {
    for _ in 0..<2_000 where !condition() {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

struct LookBackStubFailure: Error {}
