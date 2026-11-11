import Foundation
import Testing
@testable import PaeoniaApp

/// The Mail view model with the real file cache in a temporary folder and a fake server.
@MainActor
struct MailViewModelTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let me = UUID()
    private let partner = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Answers `get_older_letters` with `olderPage`. While `holds` is set, the answer waits for `release()`.
    private actor Server: MailGateway {
        private let olderPage: MailPage
        private var holds: Bool
        private var held: CheckedContinuation<Void, Never>?
        private(set) var askedForOlder = false

        init(olderPage: MailPage = MailPage(), holds: Bool = false) {
            self.olderPage = olderPage
            self.holds = holds
        }

        func release() {
            holds = false
            held?.resume()
            held = nil
        }

        func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage {
            askedForOlder = true
            if holds { await withCheckedContinuation { held = $0 } }
            return olderPage
        }

        // swiftlint:disable async_without_await
        func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? { nil }
        func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
        func delete(id: UUID, operation: SyncClientOperation) async throws {}
        func partnerTimeZoneID() async throws -> String? { nil }
        // swiftlint:enable async_without_await
    }

    private actor Evictions {
        private(set) var ids: [UUID] = []
        func add(_ evicted: [UUID]) { ids += evicted }
    }

    private func letter(_ state: LetterState, photo: UUID? = nil, hoursAgo: Double) -> Letter {
        let at = start.addingTimeInterval(-hoursAgo * 3_600)
        return Letter(
            id: UUID(), authorUserID: partner, recipientUserID: me, templateKey: .missYou, body: "Soon.",
            mediaAssetID: photo, deliveryKind: nil, deliverAt: nil, state: state,
            deliveredAt: at, openedAt: state == .opened ? at : nil, createdAt: at
        )
    }

    private func page(_ letters: [Letter], hasMore: Bool) -> MailPage {
        let cursor = letters.last.map { letter in
            LetterCursor(at: ISO8601DateFormatter().string(from: letter.deliveredAt ?? start), id: letter.id)
        }
        return MailPage(letters: letters, nextBefore: hasMore ? cursor : nil)
    }

    /// A new `cache` each call, as after the app was relaunched, unless the test passes the one it holds.
    private func mail(_ server: Server, _ evictions: Evictions, cache: FileMailCache? = nil) async -> MailViewModel {
        let mail = MailViewModel(
            cache: cache ?? FileMailCache(directoryURL: directory),
            gateway: server,
            evictPhotos: { await evictions.add($0) }
        )
        await mail.configure(ownerUserID: me, coupleID: UUID())
        return mail
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 where !(await condition()) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aPhotoFromAnOlderPageLeavesThePhoneWhenTheMailboxCloses() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = UUID()
        let newest = letter(.opened, hoursAgo: 1)
        await FileMailCache(directoryURL: directory).save(
            MailSnapshot(received: page([newest], hasMore: true)), ownerUserID: me
        )
        let evictions = Evictions()
        let older = page([letter(.opened, photo: photo, hoursAgo: 30)], hasMore: false)
        let mail = await mail(Server(olderPage: older), evictions)
        mail.present()
        await mail.loadOlder(.received)
        #expect(mail.received.count == 2)

        mail.presentation = nil
        try await waitFor { await !evictions.ids.isEmpty }
        #expect(await evictions.ids == [photo])
    }

    @Test func aLetterDeletedWhileTheAppWasClosedTakesItsPhotoWithIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = UUID()
        let cache = FileMailCache(directoryURL: directory)
        let withPhoto = page([letter(.opened, photo: photo, hoursAgo: 2)], hasMore: false)
        await cache.save(MailSnapshot(received: withPhoto), ownerUserID: me)
        let evictions = Evictions()
        _ = await mail(Server(), evictions)
        #expect(await evictions.ids.isEmpty)

        // The app ends, the author deletes the letter, and the live feed stores the new list.
        await cache.save(MailSnapshot(), ownerUserID: me)
        _ = await mail(Server(), evictions)
        #expect(await evictions.ids == [photo])
    }

    @Test func aDraftReadJustBeforeALeavePurgeLeavesMemoryWithIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileMailCache(directoryURL: directory)
        let draft = LetterDraft(content: LetterContent(templateKey: .missYou, body: "See you soon."))
        #expect(await cache.saveDraft(draft, ownerUserID: me, ifGeneration: cache.draftGeneration))
        let mail = await mail(Server(), Evictions(), cache: cache)
        #expect(mail.composer.draft == draft)

        await cache.clearDrafts()
        await mail.reload()
        #expect(mail.composer.draft == nil)
    }

    @Test func loadingOlderLettersKeepsAFirstPageLetterThatChangedMeanwhile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var newest = letter(.delivered, hoursAgo: 1)
        let cache = FileMailCache(directoryURL: directory)
        await cache.save(MailSnapshot(received: page([newest], hasMore: true)), ownerUserID: me)
        let older = letter(.opened, hoursAgo: 30)
        let server = Server(olderPage: page([older], hasMore: false), holds: true)
        let mail = await mail(server, Evictions())

        let loading = Task { await mail.loadOlder(.received) }
        try await waitFor { await server.askedForOlder }
        newest.state = .opened
        await cache.save(MailSnapshot(received: page([newest], hasMore: true)), ownerUserID: me)
        await mail.reload()
        await server.release()
        await loading.value

        #expect(mail.received.map(\.id) == [newest.id, older.id])
        #expect(mail.received.first?.state == .opened)
    }
}
