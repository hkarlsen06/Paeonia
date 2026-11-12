import Foundation
import Testing
@testable import PaeoniaApp

/// Answers as `edit_letter` does: `40001` once the letter arrived, `P0002` once it is gone, and
/// `23514` for a kept photo that is no longer the letter's photo. While `losesAnswers` is set, it
/// applies the change and then the answer never arrives, as when the request times out after the
/// server saved it. Without options, their read fails as it does offline.
private actor Server: MailGateway {
    private(set) var letters: [UUID: Letter] = [:]
    private var losesAnswers: URLError.Code?
    private var options: MailDeliveryOptions? = MailDeliveryOptions()

    func put(_ letter: Letter) { letters[letter.id] = letter }
    func loseAnswers(_ code: URLError.Code?) { losesAnswers = code }
    func setOptions(_ value: MailDeliveryOptions?) { options = value }

    // swiftlint:disable async_without_await
    func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? { nil }

    func change(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        guard let old = letters[letter.id] else {
            throw PaeoniaConvexError.server(code: "P0002", message: "letter was deleted")
        }
        guard old.state == .sealed else {
            throw PaeoniaConvexError.server(code: "40001", message: "letter already arrived")
        }
        let named = photo == nil ? letter.content.storedPhotoID : UUID()
        if photo == nil, let named, named != old.mediaAssetID {
            throw PaeoniaConvexError.server(code: "23514", message: "letter image is not usable")
        }
        letters[letter.id] = Letter(
            id: old.id, authorUserID: old.authorUserID, recipientUserID: old.recipientUserID,
            templateKey: letter.content.templateKey, body: letter.content.trimmedBody, mediaAssetID: named,
            deliveryKind: letter.content.delivery.kind, deliverAt: old.deliverAt, state: old.state,
            deliveredAt: nil, openedAt: nil, createdAt: old.createdAt
        )
        if let losesAnswers { throw URLError(losesAnswers) }
        return letters[letter.id]
    }

    func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
    func delete(id: UUID, operation: SyncClientOperation) async throws { letters[id] = nil }
    func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage { MailPage() }
    func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions {
        guard let options else { throw URLError(.notConnectedToInternet) }
        return options
    }
    // swiftlint:enable async_without_await
}

/// What the author is told, and what the change becomes, when a save of a change ends without a
/// clear answer, the letter changed elsewhere, or a default time no longer holds.
@MainActor
struct MailChangeOutcomeTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let me = UUID()
    private let couple = UUID()

    private final class Operations: SyncClientOperationProviding {
        func makeOperation() -> SyncClientOperation {
            SyncClientOperation(clientID: UUID(), clientSequence: 1)
        }
    }

    private func sealed(photo: UUID?) -> Letter {
        Letter(
            id: UUID(), authorUserID: me, recipientUserID: UUID(), templateKey: .goodNight, body: "Sleep well.",
            mediaAssetID: photo, deliveryKind: .at, deliverAt: .now.addingTimeInterval(86_400), state: .sealed,
            deliveredAt: nil, openedAt: nil, createdAt: .now
        )
    }

    private func mail(_ server: Server, showing sent: [Letter] = []) async -> (MailViewModel, FileMailCache) {
        let cache = FileMailCache(directoryURL: directory)
        await cache.save(MailSnapshot(sent: MailPage(letters: sent)), ownerUserID: me)
        let mail = MailViewModel(cache: cache, gateway: server, evictPhotos: { _ in })
        await mail.configure(ownerUserID: me, coupleID: couple)
        return (mail, cache)
    }

    @Test func aChangeWhoseAnswerIsLostIsNotCalledUnsavedAndSettlesWhenTheLetterShowsIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Server()
        let letter = sealed(photo: nil)
        await server.put(letter)
        let (mail, cache) = await mail(server, showing: [letter])
        #expect(mail.change(letter))
        mail.composer.updateBody("I'm sorry about last night.")
        await server.loseAnswers(.timedOut)

        await mail.send()
        #expect(mail.notice?.error == .changeUnconfirmed)
        #expect(mail.composer.draft?.unconfirmed == true)

        // The live feed brings the letter as the server has it, holding the change.
        let landed = try #require(await server.letters[letter.id])
        await cache.save(MailSnapshot(sent: MailPage(letters: [landed])), ownerUserID: me)
        await mail.reload()
        #expect(mail.composer.draft == nil)
        #expect(mail.composer.sentLetterID == letter.id)
    }

    @Test func aDroppedConnectionAfterTheRequestLeftIsNotCalledUnsaved() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Server()
        let letter = sealed(photo: nil)
        await server.put(letter)
        let composer = LetterComposer(
            cache: FileMailCache(directoryURL: directory), gateway: server, operationProvider: Operations()
        )
        await composer.load(ownerUserID: me)
        #expect(composer.startChange(of: letter))
        composer.updateBody("See you Friday.")
        await server.loseAnswers(.networkConnectionLost)
        #expect(await composer.send(coupleID: couple) == .failed(.changeUnconfirmedOffline))
        #expect(composer.draft?.unconfirmed == true)

        // A letter on the list without the change leaves it to the next save, which is a replay.
        #expect(composer.settleChange([letter]) == .ignored)
        await server.loseAnswers(nil)
        let second = await composer.send(coupleID: couple)
        guard case .sent = second else {
            Issue.record("expected the second save to land")
            return
        }
        #expect(composer.draft == nil)
    }

    @Test func aPhotoAnotherPhoneReplacedIsTakenFromTheLetterSoTheWordsCanBeSaved() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Server()
        let shownWhenOpened = sealed(photo: UUID())
        let current = Letter(
            id: shownWhenOpened.id, authorUserID: me, recipientUserID: shownWhenOpened.recipientUserID,
            templateKey: .goodNight, body: "Sleep well.", mediaAssetID: UUID(), deliveryKind: .at,
            deliverAt: shownWhenOpened.deliverAt, state: .sealed, deliveredAt: nil, openedAt: nil, createdAt: .now
        )
        await server.put(current)
        let (mail, cache) = await mail(server, showing: [shownWhenOpened])
        #expect(mail.change(shownWhenOpened))
        mail.composer.updateBody("Sleep well. See you Friday.")
        // The other phone's change reaches this phone's list.
        await cache.save(MailSnapshot(sent: MailPage(letters: [current])), ownerUserID: me)
        await mail.reload()

        await mail.send()
        #expect(mail.notice?.error == .changePhotoChanged)
        #expect(mail.composer.draft?.content.storedPhotoID == current.mediaAssetID)
        #expect(mail.composer.draft?.content.body == "Sleep well. See you Friday.")
        await mail.send()
        #expect(mail.composer.draft == nil)
        #expect(await server.letters[current.id]?.body == "Sleep well. See you Friday.")
    }

    private func birthdayInTenDays() throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day = try #require(calendar.date(byAdding: .day, value: 10, to: .now))
        let parts = calendar.dateComponents([.month, .day], from: day)
        return String(format: "2000-%02d-%02d", parts.month ?? 1, parts.day ?? 1)
    }

    @Test func aBirthdayCardKeepsItsBirthdayWhileTheOptionsAreUnknown() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Server()
        await server.setOptions(MailDeliveryOptions(partnerTimeZoneID: "UTC", partnerBirthday: try birthdayInTenDays()))
        let (first, cache) = await mail(server)
        first.composer.choose(LetterTemplate(.birthday))
        first.composer.updateStep(.delivery)
        await first.loadDeliveryOptions()
        guard case let .at(birthday)? = first.composer.draft?.content.delivery else {
            Issue.record("expected the birthday morning")
            return
        }

        await server.setOptions(nil)
        await first.loadDeliveryOptions()
        #expect(first.composer.draft?.content.delivery == .at(birthday))

        // After a relaunch the delivery step appears before the options arrive.
        await first.composer.load(ownerUserID: me)
        let relaunched = MailViewModel(cache: cache, gateway: server, evictPhotos: { _ in })
        await relaunched.configure(ownerUserID: me, coupleID: couple)
        relaunched.suggestDelivery()
        #expect(relaunched.composer.draft?.content.delivery == .at(birthday))
    }

    @Test func aBirthdayMorningThatPassesOnScreenSendsTheCardAtOnceAndSaysSo() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let iso = ISO8601DateFormatter()
        let eve = try #require(iso.date(from: "2026-11-20T07:00:00Z"))
        let later = try #require(iso.date(from: "2026-11-21T09:00:00Z"))
        let composer = LetterComposer(
            cache: FileMailCache(directoryURL: directory), gateway: Server(), operationProvider: Operations()
        )
        await composer.load(ownerUserID: me)
        composer.choose(LetterTemplate(.birthday))
        composer.updateBody("Happy birthday, Robin!")
        composer.suggestDelivery(partnerBirthday: "2000-11-20", timeZone: utc, now: eve)
        #expect(!composer.moveTimeIfPassed(now: later))

        #expect(await composer.send(coupleID: couple, now: later) == .failed(.birthdayPassed))
        #expect(composer.draft?.content.delivery == .now)
        #expect(composer.draft?.birthdayArrival == nil)
        #expect(!composer.movedPastTime)
    }

    @Test func unsendingALetterEndsItsChangeAndKeepsOnlyNewWords() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Server()
        let untouched = sealed(photo: nil)
        let edited = sealed(photo: nil)
        await server.put(untouched)
        await server.put(edited)
        let (mail, _) = await mail(server, showing: [untouched, edited])

        #expect(mail.change(untouched))
        #expect(await mail.delete(untouched))
        #expect(mail.composer.draft == nil)

        #expect(mail.change(edited))
        mail.composer.updateBody("New words")
        #expect(await mail.delete(edited))
        #expect(mail.composer.draft?.changing == nil)
        #expect(mail.composer.draft?.content.body == "New words")
        #expect(mail.notice == nil)
    }
}
