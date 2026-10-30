#if DEBUG
import SwiftUI
import UIKit

nonisolated extension DeveloperScenario {
    static let avatarStoriesNew = DeveloperScenario(
        "avatar-stories-new", "Avatars, new story",
        "Decorations, your story and plus, an unseen partner story", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .duringReveal, avatarStories: .unseen) }
    static let avatarStoriesSeen = DeveloperScenario(
        "avatar-stories-seen", "Avatars, seen story", "Decorations with an already viewed partner story", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .duringReveal, avatarStories: .seen) }
    static let avatarStoriesEmpty = DeveloperScenario(
        "avatar-stories-empty", "Avatars, no partner story", "Decorations without a partner story", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .duringReveal, avatarStories: .noStory) }
}

enum DeveloperAvatarFixture {
    nonisolated static func decoration(for person: String, default fallback: AvatarDecoration) -> AvatarDecoration {
        let value = UserDefaults.standard.string(forKey: "avatar-frame-\(person)") ?? ""
        return AvatarDecoration(rawValue: value) ?? fallback
    }

    nonisolated static let ownPhoto = UUID(uuidString: "1e61a671-473d-421a-a881-420e6f148003") ?? UUID()
    nonisolated static let partnerPhoto = UUID(uuidString: "1e61a671-473d-421a-a881-420e6f148001") ?? UUID()
    nonisolated static let storyPhoto = UUID(uuidString: "1e61a671-473d-421a-a881-420e6f148002") ?? UUID()

    static func stories(_ state: StoryRingState) -> StoriesViewModel {
        seedPhotos()
        let now = Date()
        var stories = [Story(
            id: UUID(), authorUserID: DeveloperScenarioFixture.currentUserID,
            mediaAssetID: storyPhoto, caption: "A little moment from today", createdAt: now, seenAt: nil
        )]
        if state != .noStory {
            stories.append(Story(
                id: UUID(), authorUserID: DeveloperScenarioFixture.partnerUserID,
                mediaAssetID: storyPhoto, caption: "Wish you were here", createdAt: now,
                seenAt: state == .seen ? now : nil
            ))
        }
        let snapshot = StoriesSnapshot(stories: stories, notes: [
            StoryNote(userID: DeveloperScenarioFixture.partnerUserID, text: "Thinking of you", createdAt: now)
        ])
        let defaults = UserDefaults(suiteName: "avatar-scenario-\(UUID().uuidString)") ?? .standard
        return StoriesViewModel(
            cache: DeveloperAvatarStoriesCache(snapshot), gateway: DeveloperAvatarStoriesGateway(),
            operationProvider: DeveloperScenarioOperationProvider(), defaults: defaults
        )
    }

    private static func seedPhotos() {
        // Existing marketing portraits.
        for id in [ownPhoto, partnerPhoto] {
            if let data = photoData(for: id), let photo = UIImage(data: data) {
                PaeoniaImageMemoryCache.store(photo, for: id)
            }
        }
        if let url = Bundle.main.url(forResource: "scenario-memory-oslo-opera", withExtension: "jpg"),
           let photo = UIImage(contentsOfFile: url.path) {
            MemoryImageDecoding.store(photo, for: storyPhoto, maxPixelSize: StoryPhotoView.maxPixelSize)
        }
    }

    nonisolated static func photoData(for mediaAssetID: UUID?) -> Data? {
        let resource: (name: String, fileExtension: String)
        switch mediaAssetID {
        case ownPhoto: resource = ("scenario-memory-avatar-alex", "webp")
        case partnerPhoto: resource = ("scenario-memory-avatar-robin", "jpg")
        default: return nil
        }
        guard let url = Bundle.main.url(forResource: resource.name, withExtension: resource.fileExtension) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}

struct DeveloperAvatarDecorationGateway: AvatarDecorationSaving {
    let store: DeveloperLocalFlowStore

    func save(_ decoration: AvatarDecoration) async throws {
        await store.setAvatarDecoration(decoration)
    }
}

nonisolated struct DeveloperAvatarPhotoProvider: ProfilePhotoImageProviding {
    // swiftlint:disable:next async_without_await
    func profilePhotoData(for mediaAssetID: UUID?) async -> Data? {
        DeveloperAvatarFixture.photoData(for: mediaAssetID)
    }
}

actor DeveloperAvatarStoriesCache: StoriesCaching {
    private var value: StoriesSnapshot
    private(set) var purgeGeneration = 0

    init(_ value: StoriesSnapshot) { self.value = value }
    func snapshot(ownerUserID: UUID) -> StoriesSnapshot { value }
    func save(_ snapshot: StoriesSnapshot, ownerUserID: UUID) { value = snapshot }
    func update(
        ownerUserID: UUID, ifGeneration generation: Int, _ change: @Sendable (inout StoriesSnapshot) -> Void
    ) -> Bool {
        guard generation == purgeGeneration else { return false }
        change(&value)
        return true
    }
    func clearAll() {
        purgeGeneration += 1
        value = StoriesSnapshot()
    }
}

// Protocol methods replace the network boundary with local results.
// swiftlint:disable async_without_await
struct DeveloperAvatarStoriesGateway: StoriesGateway {
    func post(id: UUID, photo: MemoryUploadMedia, caption: String?, coupleID: UUID,
              operations: StoryPostOperations) async throws -> Story? {
        Story(id: id, authorUserID: DeveloperScenarioFixture.currentUserID,
              mediaAssetID: DeveloperAvatarFixture.storyPhoto, caption: caption, createdAt: .now, seenAt: nil)
    }
    func delete(id: UUID, operation: SyncClientOperation) async throws {}
    func markSeen(id: UUID) async throws {}
    func setNote(_ text: String?, operation: SyncClientOperation) async throws -> StoryNote? {
        text.map { StoryNote(userID: DeveloperScenarioFixture.currentUserID, text: $0, createdAt: .now) }
    }
}
// swiftlint:enable async_without_await
#endif
