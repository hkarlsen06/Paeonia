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

    /// Stores each letter once by its id, like `send_letter`, and answers with the letter as it
    /// was first stored. While `holds` is set a send waits for `release()`, and while
    /// `losesAnswers` is set its answer never arrives.
    private actor Mailroom: MailGateway {
        private(set) var stored: [LetterSend] = []
        private var holds: Bool
        private var held: CheckedContinuation<Void, Never>?
        private var losesAnswers = true

        init(holds: Bool) {
            self.holds = holds
        }

        func release() {
            holds = false
            held?.resume()
            held = nil
        }

        func answerFromNowOn() {
            losesAnswers = false
        }

        func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
            if !stored.contains(where: { $0.id == letter.id }) { stored.append(letter) }
            if holds { await withCheckedContinuation { held = $0 } }
            if losesAnswers { throw URLError(.timedOut) }
            return stored.first { $0.id == letter.id }.map { first in
                Letter(
                    id: first.id, authorUserID: UUID(), recipientUserID: UUID(),
                    templateKey: first.content.templateKey, body: first.content.trimmedBody, mediaAssetID: nil,
                    deliveryKind: .now, deliverAt: nil, state: .delivered, deliveredAt: .now, openedAt: nil,
                    createdAt: .now
                )
            }
        }

        // swiftlint:disable async_without_await
        func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
        func delete(id: UUID, operation: SyncClientOperation) async throws {}
        func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage { MailPage() }
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

    @Test func aLetterTheFeedShowedWhileItsSendFailedClosesTheComposer() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileMailCache(directoryURL: directory)
        let server = Mailroom(holds: true)
        let mail = MailViewModel(cache: cache, gateway: server, evictPhotos: { _ in })
        await mail.configure(ownerUserID: me, coupleID: UUID())
        mail.composer.choose(LetterTemplate(.missYou))
        mail.composer.updateBody("See you.")

        let sending = Task { await mail.send() }
        for _ in 0..<500 where await server.stored.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let letterID = try #require(await server.stored.first?.id)
        // The live feed stores the sent list with the letter while the request still waits.
        let sent = Letter(
            id: letterID, authorUserID: me, recipientUserID: partner, templateKey: .missYou, body: "See you.",
            mediaAssetID: nil, deliveryKind: .now, deliverAt: nil, state: .delivered, deliveredAt: .now,
            openedAt: nil, createdAt: .now
        )
        await cache.save(MailSnapshot(sent: MailPage(letters: [sent])), ownerUserID: me)
        await mail.reload()
        // Then the answer is lost.
        await server.release()
        await sending.value

        #expect(mail.composer.draft == nil)
        #expect(mail.composer.sentLetterID == letterID)
        #expect(mail.notice == nil)
    }

    @Test func changesMadeAfterALetterAlreadyWentStayAndTheAuthorIsTold() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Mailroom(holds: false)
        let mail = MailViewModel(
            cache: FileMailCache(directoryURL: directory), gateway: server, evictPhotos: { _ in }
        )
        await mail.configure(ownerUserID: me, coupleID: UUID())
        mail.composer.choose(LetterTemplate(.missYou))
        mail.composer.updateBody("See you.")
        // The server stores the letter, and the answer is lost.
        await mail.send()
        let failed = try #require(mail.notice)
        #expect(mail.takeNotice(failed.id) == .sendFailed)

        mail.composer.updateBody("See you. P.S. I booked the train for Friday.")
        await server.answerFromNowOn()
        await mail.send()

        #expect(mail.sent.first?.body == "See you.")
        #expect(mail.notice?.error == .changesNotAdded)
        #expect(mail.composer.draft?.content.trimmedBody == "See you. P.S. I booked the train for Friday.")

        // Sending what stayed makes a second letter with the changes in it.
        await mail.send()
        #expect(mail.composer.draft == nil)
        let notes = await server.stored.map(\.content.trimmedBody)
        #expect(notes == ["See you.", "See you. P.S. I booked the train for Friday."])
    }
}
