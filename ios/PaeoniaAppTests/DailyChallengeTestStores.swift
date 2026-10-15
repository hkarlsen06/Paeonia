import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
final class InMemoryDailyChallengeDraftStore: DailyChallengeDraftStoring {
    private var storage: [UUID: [UUID: DailyAnswerDraft]] = [:]

    func drafts(for userID: UUID) -> [UUID: DailyAnswerDraft] {
        storage[userID] ?? [:]
    }

    func setDraft(_ draft: DailyAnswerDraft, for instanceID: UUID, userID: UUID) {
        if draft.hasContent {
            storage[userID, default: [:]][instanceID] = draft
        } else {
            storage[userID]?[instanceID] = nil
        }
    }

    func clearDraft(for instanceID: UUID, userID: UUID) {
        storage[userID]?[instanceID] = nil
    }
}

@MainActor
final class FixedDailyChallengeOperationProvider: SyncClientOperationProviding {
    func makeOperation() -> SyncClientOperation {
        SyncClientOperation(
            id: dailyFixedUUID("55555555-5555-5555-5555-555555555555"),
            clientID: dailyFixedUUID("66666666-6666-6666-6666-666666666666"),
            clientSequence: 1,
            localCreatedAt: TestDailyChallengeIDs.answerDate
        )
    }
}

actor RecordingMediaUploadService: DailyAnswerMediaUploading {
    let assetID: UUID
    private(set) var uploadCount = 0
    private(set) var lastAnswerID: UUID?
    private(set) var lastCoupleID: UUID?

    init(assetID: UUID) {
        self.assetID = assetID
    }

    func uploadMedia(
        _: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation _: SyncClientOperation,
        finalizeOperation _: SyncClientOperation
    ) throws -> UUID {
        uploadCount += 1
        lastAnswerID = answerID
        lastCoupleID = coupleID
        return assetID
    }
}

final class InMemoryDailyAnswerMediaDraftStore: DailyAnswerMediaDraftStoring, @unchecked Sendable {
    private var storage: [UUID: Data] = [:]

    func writeStagedMedia(_ data: Data, instanceID: UUID) throws {
        storage[instanceID] = data
    }

    func stagedMediaData(instanceID: UUID) -> Data? {
        storage[instanceID]
    }

    func removeStagedMedia(instanceID: UUID) {
        storage[instanceID] = nil
    }

    func clearAll() {
        storage.removeAll()
    }
}
