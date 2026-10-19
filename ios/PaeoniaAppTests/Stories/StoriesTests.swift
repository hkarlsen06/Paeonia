import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

nonisolated private enum StoryFixture {
    static let me = UUID()
    static let partner = UUID()
    static let couple = UUID()
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func story(by author: UUID, hoursAgo: Double, seen: Bool = false) -> Story {
        let createdAt = now.addingTimeInterval(-hoursAgo * 3_600)
        return Story(
            id: UUID(),
            authorUserID: author,
            mediaAssetID: UUID(),
            caption: nil,
            createdAt: createdAt,
            seenAt: seen ? createdAt.addingTimeInterval(60) : nil
        )
    }

    static let photo: Data = {
        let size = CGSize(width: 40, height: 30)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 1) { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()
}

struct StoryTimelineTests {
    @Test func homeShowsOnlyTheAuthorsStoriesFromTheLastDayOldestFirst() {
        let newer = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 1)
        let older = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 23)
        let expired = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 25)
        let mine = StoryFixture.story(by: StoryFixture.me, hoursAgo: 2)

        let shown = StoryTimeline.onHome(
            [newer, mine, expired, older],
            author: StoryFixture.partner,
            at: StoryFixture.now
        )

        #expect(shown.map(\.id) == [older.id, newer.id])
    }

    @Test func aStoryLeavesHomeExactlyADayAfterItWasPosted() {
        let story = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 0)
        #expect(story.isOnHome(at: story.createdAt.addingTimeInterval(Story.lifetime - 1)))
        #expect(!story.isOnHome(at: story.createdAt.addingTimeInterval(Story.lifetime)))
    }

    @Test func decodesTheServerList() throws {
        let json = """
        {"couple_id":"\(StoryFixture.couple.uuidString.lowercased())","stories":[
          {"id":"\(UUID().uuidString.lowercased())","author_user_id":"\(StoryFixture.partner.uuidString.lowercased())",
           "media_asset_id":"\(UUID().uuidString.lowercased())","caption":"Thinking of you",
           "created_at":"2026-10-16T08:30:00.123Z","seen_at":null}
        ],"notes":[{"user_id":"\(StoryFixture.partner.uuidString.lowercased())","text":"coffee?",
          "created_at":"2026-10-16T08:31:00.000Z"}]}
        """
        let remote = try PaeoniaConvexClient.decoder.decode(RemoteStories.self, from: Data(json.utf8))
        let story = try #require(remote.stories.first)
        #expect(story.authorUserID == StoryFixture.partner)
        #expect(story.caption == "Thinking of you")
        #expect(story.seenAt == nil)
        #expect(remote.notes.first?.text == "coffee?")
    }

    @Test func aNoteShowsForADayAndOnlyForItsAuthor() {
        let note = StoryNote(userID: StoryFixture.partner, text: "hi", createdAt: StoryFixture.now)
        let snapshot = StoriesSnapshot(notes: [note])
        #expect(snapshot.note(of: StoryFixture.partner, at: StoryFixture.now)?.text == "hi")
        #expect(snapshot.note(of: StoryFixture.me, at: StoryFixture.now) == nil)
        let later = StoryFixture.now.addingTimeInterval(Story.lifetime)
        #expect(snapshot.note(of: StoryFixture.partner, at: later) == nil)
    }
}

@MainActor
struct StoriesViewModelTests {
    private func makeModel(
        gateway: FakeStoriesGateway,
        cache: InMemoryStoriesCache = InMemoryStoriesCache()
    ) async -> StoriesViewModel {
        let model = StoriesViewModel(
            cache: cache,
            gateway: gateway,
            operationProvider: MemoryTestOperationProvider(),
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        await model.configure(ownerUserID: StoryFixture.me, coupleID: StoryFixture.couple)
        return model
    }

    @Test func aSharedStoryShowsAtOnceAndIsRememberedAsPosted() async {
        let gateway = FakeStoriesGateway()
        let cache = InMemoryStoriesCache()
        let model = await makeModel(gateway: gateway, cache: cache)
        #expect(!model.hasPostedBefore)

        let posted = await model.post(photo: StoryFixture.photo, caption: "  hello  ")
        await model.reload()

        #expect(posted)
        #expect(model.hasPostedBefore)
        #expect(model.stories.count == 1)
        #expect(model.stories.first?.caption == "hello")
        #expect(await gateway.posts.first?.caption == "hello")
        #expect(await cache.snapshot(ownerUserID: StoryFixture.me).stories.count == 1)
    }

    @Test func tryingAgainAfterAFailedPostSendsTheSameStory() async {
        let gateway = FakeStoriesGateway()
        await gateway.failNextPost()
        let model = await makeModel(gateway: gateway)

        let first = await model.post(photo: StoryFixture.photo, caption: "hi")
        #expect(!first)
        #expect(model.error == .postFailed)
        let retry = await model.post(photo: StoryFixture.photo, caption: "hi")
        #expect(retry)

        let posts = await gateway.posts
        #expect(posts.count == 2)
        #expect(posts[0].id == posts[1].id)
        #expect(posts[0].postOperationID == posts[1].postOperationID)
    }

    @Test func openingThePartnersStoryMarksItSeenHereAndOnTheServer() async throws {
        let gateway = FakeStoriesGateway()
        let cache = InMemoryStoriesCache()
        let story = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 1)
        await cache.save(StoriesSnapshot(stories: [story]), ownerUserID: StoryFixture.me)
        let model = await makeModel(gateway: gateway, cache: cache)

        model.markSeen(story)
        try await waitUntil { await gateway.seenIDs == [story.id] }

        #expect(await cache.snapshot(ownerUserID: StoryFixture.me).stories.first?.seenAt != nil)
    }

    @Test func aFailedSeenMarkUndoesItSoTheNextOpenTriesAgain() async throws {
        let gateway = FakeStoriesGateway()
        await gateway.failSeen()
        let cache = InMemoryStoriesCache()
        let story = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 1)
        await cache.save(StoriesSnapshot(stories: [story]), ownerUserID: StoryFixture.me)
        let model = await makeModel(gateway: gateway, cache: cache)

        model.markSeen(story)
        try await waitUntil { await gateway.seenIDs == [story.id] }
        try await Task.sleep(for: .milliseconds(50))

        #expect(await cache.snapshot(ownerUserID: StoryFixture.me).stories.first?.seenAt == nil)
    }

    @Test func anAnswerThatArrivesAfterAPurgeWritesNothing() async {
        let gateway = FakeStoriesGateway()
        let cache = InMemoryStoriesCache()
        await gateway.runBeforeAnswer { await cache.clearAll() }
        let model = await makeModel(gateway: gateway, cache: cache)

        let posted = await model.post(photo: StoryFixture.photo, caption: "hi")
        let saved = await model.setNote("hi")

        #expect(posted)
        #expect(saved)
        #expect(await cache.snapshot(ownerUserID: StoryFixture.me) == StoriesSnapshot())
    }

    @Test func deletingRemovesTheStoryAndOnlyTheAuthorCanDelete() async {
        let gateway = FakeStoriesGateway()
        let cache = InMemoryStoriesCache()
        let mine = StoryFixture.story(by: StoryFixture.me, hoursAgo: 1)
        let theirs = StoryFixture.story(by: StoryFixture.partner, hoursAgo: 1)
        await cache.save(StoriesSnapshot(stories: [mine, theirs]), ownerUserID: StoryFixture.me)
        let model = await makeModel(gateway: gateway, cache: cache)

        let deletedTheirs = await model.delete(theirs)
        let deletedMine = await model.delete(mine)
        #expect(!deletedTheirs)
        #expect(deletedMine)
        await model.reload()

        #expect(model.stories.map(\.id) == [theirs.id])
        #expect(await gateway.deletedIDs == [mine.id])
    }

    @Test func anOfflineDeleteKeepsTheStoryAndSaysWhy() async {
        let gateway = FakeStoriesGateway()
        await gateway.failDeletes(with: URLError(.notConnectedToInternet))
        let cache = InMemoryStoriesCache()
        let mine = StoryFixture.story(by: StoryFixture.me, hoursAgo: 1)
        await cache.save(StoriesSnapshot(stories: [mine]), ownerUserID: StoryFixture.me)
        let model = await makeModel(gateway: gateway, cache: cache)

        let deleted = await model.delete(mine)
        #expect(!deleted)
        #expect(model.error == .deleteOffline)
        #expect(model.stories.map(\.id) == [mine.id])
    }

    @Test func aSavedNoteReplacesTheOldOneAndBlankRemovesIt() async {
        let gateway = FakeStoriesGateway()
        let cache = InMemoryStoriesCache()
        let old = StoryNote(userID: StoryFixture.me, text: "old", createdAt: StoryFixture.now)
        let partners = StoryNote(userID: StoryFixture.partner, text: "theirs", createdAt: StoryFixture.now)
        await cache.save(StoriesSnapshot(notes: [old, partners]), ownerUserID: StoryFixture.me)
        let model = await makeModel(gateway: gateway, cache: cache)

        let saved = await model.setNote("  new  ")
        await model.reload()
        #expect(saved)
        #expect(Set(model.notes.map(\.text)) == ["new", "theirs"])

        let removed = await model.setNote("   ")
        await model.reload()
        #expect(removed)
        #expect(model.notes.map(\.text) == ["theirs"])
        #expect(await gateway.noteTexts == ["new", nil])
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The condition never became true")
    }
}

actor InMemoryStoriesCache {
    private var byOwner: [UUID: StoriesSnapshot] = [:]
    private(set) var purgeGeneration = 0

    func snapshot(ownerUserID: UUID) -> StoriesSnapshot {
        byOwner[ownerUserID] ?? StoriesSnapshot()
    }

    func save(_ snapshot: StoriesSnapshot, ownerUserID: UUID) {
        byOwner[ownerUserID] = snapshot
    }

    func update(
        ownerUserID: UUID,
        ifGeneration generation: Int,
        _ change: @Sendable (inout StoriesSnapshot) -> Void
    ) -> Bool {
        guard generation == purgeGeneration else { return false }
        var updated = snapshot(ownerUserID: ownerUserID)
        change(&updated)
        byOwner[ownerUserID] = updated
        return true
    }

    func clearAll() {
        purgeGeneration += 1
        byOwner = [:]
    }
}

extension InMemoryStoriesCache: StoriesCaching {}

actor FakeStoriesGateway {
    nonisolated struct Post: Equatable, Sendable {
        let id: UUID
        let caption: String?
        let postOperationID: UUID
    }

    private(set) var posts: [Post] = []
    private(set) var deletedIDs: [UUID] = []
    private(set) var seenIDs: [UUID] = []
    private(set) var noteTexts: [String?] = []
    private var failsNextPost = false
    private var deleteError: (any Error)?
    private var noteError: (any Error)?
    private var seenFails = false
    /// Runs before a post or note answers, like a purge that lands while the call is out.
    private var beforeAnswer: (@Sendable () async -> Void)?

    func failSeen() {
        seenFails = true
    }

    func runBeforeAnswer(_ action: @escaping @Sendable () async -> Void) {
        beforeAnswer = action
    }

    func failNotes(with error: any Error) {
        noteError = error
    }

    func setNote(_ text: String?, operation: SyncClientOperation) async throws -> StoryNote? {
        if let noteError { throw noteError }
        await beforeAnswer?()
        noteTexts.append(text)
        return text.map { StoryNote(userID: StoryFixture.me, text: $0, createdAt: Date()) }
    }

    func failNextPost() {
        failsNextPost = true
    }

    func failDeletes(with error: any Error) {
        deleteError = error
    }

    func post(
        id: UUID,
        photo: MemoryUploadMedia,
        caption: String?,
        coupleID: UUID,
        operations: StoryPostOperations
    ) async throws -> Story? {
        posts.append(Post(id: id, caption: caption, postOperationID: operations.post.id))
        await beforeAnswer?()
        if failsNextPost {
            failsNextPost = false
            throw URLError(.timedOut)
        }
        return Story(
            id: id,
            authorUserID: StoryFixture.me,
            mediaAssetID: UUID(),
            caption: caption,
            createdAt: Date(),
            seenAt: nil
        )
    }

    func delete(id: UUID, operation: SyncClientOperation) throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
    }

    func markSeen(id: UUID) throws {
        seenIDs.append(id)
        if seenFails { throw URLError(.timedOut) }
    }
}

extension FakeStoriesGateway: StoriesGateway {}
