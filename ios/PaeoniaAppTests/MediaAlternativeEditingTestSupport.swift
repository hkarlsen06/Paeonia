import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct MediaAlternativeEditingFixture {
    let owner = UUID()
    let couple = UUID()
    let assetID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let localStore: PaeoniaLocalStore
    let chat: FileThreadChatCache
    let stories: FileStoriesCache
    let pending: SwiftDataPendingSyncOperationRepository
    let operations = ChatTestOperationProvider()
    let message: ThreadChatMessage

    init() throws {
        localStore = try PaeoniaLocalStore(inMemory: true)
        chat = FileThreadChatCache(directoryURL: directory.appendingPathComponent("chat"))
        stories = FileStoriesCache(directoryURL: directory.appendingPathComponent("stories"))
        pending = SwiftDataPendingSyncOperationRepository(container: localStore.container)
        message = ThreadChatMessage(id: UUID(), threadID: UUID(), subjectID: UUID(), senderUserID: owner,
                                    body: "Original message", createdAt: Date(timeIntervalSince1970: 1),
                                    clientOperationID: nil, isSending: false,
                                    voice: ThreadChatVoice(
                                        mediaAssetID: assetID, data: Data([1, 2]), durationMs: 1_000,
                                        transcript: "Original transcript"
                                    ))
    }

    var target: MediaAlternativeTarget { .chat(messageID: message.id, mediaAssetID: assetID) }
    var caches: MediaAlternativeCacheUpdater {
        MediaAlternativeCacheUpdater(chat: chat, stories: stories,
                                      daily: FileDailyChallengeSnapshotCache(
                                        directoryURL: directory.appendingPathComponent("daily")
                                      ))
    }
    var service: MediaAlternativeEditingService { MediaAlternativeEditingService(pending: pending, cache: caches) }
    var context: SyncContext { chatSyncContext(ownerUserID: owner, pendingStore: pending) }
    func edit(_ text: String) -> MediaAlternativeEdit {
        MediaAlternativeEdit(coupleID: couple, target: target, text: text)
    }
    func queue(_ edit: MediaAlternativeEdit) async throws {
        try await service.queue(edit, ownerUserID: owner, operation: operations.makeOperation(),
                                stamp: await caches.stamp(ownerUserID: owner))
    }
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}
