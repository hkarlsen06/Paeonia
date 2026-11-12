import Foundation
import Testing
@testable import PaeoniaApp

struct LetterBirthdayDeliveryTests {
    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func arrival(_ birthday: String, in zone: String, after now: String) throws -> String {
        let timeZone = try #require(TimeZone(identifier: zone))
        return switch LetterDelivery.birthdayMorning(birthday, in: timeZone, after: try date(now)) {
        case let .at(date)?: ISO8601DateFormatter().string(from: date)
        case .now?: "now"
        default: "none"
        }
    }

    @Test func isEightInTheMorningOnThePartnersNextBirthdayOnTheirClock() throws {
        #expect(try arrival("1998-11-20", in: "Asia/Tokyo", after: "2026-11-10T20:00:00Z") == "2026-11-19T23:00:00Z")
        #expect(try arrival("1998-11-11", in: "Asia/Tokyo", after: "2026-11-10T20:00:00Z") == "2026-11-10T23:00:00Z")
        #expect(try arrival("1998-11-11", in: "Asia/Tokyo", after: "2026-11-11T00:00:00Z") == "now")
        #expect(try arrival("1998-11-10", in: "Asia/Tokyo", after: "2026-11-10T20:00:00Z") == "2027-11-09T23:00:00Z")
        #expect(try arrival("1998-13-40", in: "Asia/Tokyo", after: "2026-11-10T20:00:00Z") == "none")
    }

    @Test func aBirthdayOn29FebruaryFallsOn28FebruaryInOtherYears() throws {
        #expect(try arrival("2000-02-29", in: "Europe/Oslo", after: "2026-11-10T20:00:00Z") == "2027-02-28T07:00:00Z")
        #expect(try arrival("2000-02-29", in: "Europe/Oslo", after: "2027-03-01T12:00:00Z") == "2028-02-29T07:00:00Z")
    }

    /// `send_letter` takes a set time up to 366 days ahead (`MAX_LETTER_WAIT_MS`), and the
    /// composer's time picker offers 365 unless the time it shows is later.
    @Test func theLatestBirthdayMorningFitsTheYearALetterMayWait() throws {
        let now = try date("2027-03-01T10:00:00Z")
        let zone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        guard case let .at(arrival)? = LetterDelivery.birthdayMorning("1990-03-01", in: zone, after: now) else {
            Issue.record("expected a set time")
            return
        }
        #expect(ISO8601DateFormatter().string(from: arrival) == "2028-02-29T18:00:00Z")
        #expect(arrival.timeIntervalSince(now) > 365 * 86_400)
        #expect(arrival.timeIntervalSince(now) < 366 * 86_400)
    }
}

/// Keeps letters by id. A change is applied once per operation, and a repeat of the same
/// operation is a replay. A letter that arrived is refused with `40001`, a missing one with
/// `P0002`. While `offline`, nothing reaches it. While `losesAnswers`, it applies the change
/// and the answer never arrives.
private actor Post: MailGateway {
    private(set) var letters: [UUID: Letter] = [:]
    private(set) var sends: [LetterSend] = []
    private(set) var changes: [LetterSend] = []
    private var applied: Set<UUID> = []
    private var offline = false
    private var losesAnswers = false
    private var refusesMeeting = false

    func put(_ letter: Letter) { letters[letter.id] = letter }
    func arrive(_ id: UUID) { letters[id]?.state = .delivered }
    func goOffline(_ value: Bool) { offline = value }
    func loseAnswers(_ value: Bool) { losesAnswers = value }
    func refuseMeeting(_ value: Bool) { refusesMeeting = value }

    // swiftlint:disable async_without_await
    func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        sends.append(letter)
        return nil
    }

    func change(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
        changes.append(letter)
        if offline { throw URLError(.notConnectedToInternet) }
        if !applied.contains(letter.operations.send.id) {
            guard let old = letters[letter.id] else {
                throw PaeoniaConvexError.server(code: "P0002", message: "letter was deleted")
            }
            guard old.state == .sealed else {
                throw PaeoniaConvexError.server(code: "40001", message: "letter already arrived")
            }
            if refusesMeeting, letter.content.delivery == .together, old.deliveryKind != .together {
                throw PaeoniaConvexError.server(code: "55000", message: "the next meeting needs a visit ahead")
            }
            letters[letter.id] = Letter(
                id: old.id, authorUserID: old.authorUserID, recipientUserID: old.recipientUserID,
                templateKey: letter.content.templateKey, body: letter.content.trimmedBody,
                mediaAssetID: photo == nil ? letter.content.storedPhotoID : UUID(),
                deliveryKind: letter.content.delivery.kind, deliverAt: old.deliverAt, state: old.state,
                deliveredAt: nil, openedAt: nil, createdAt: old.createdAt
            )
            applied.insert(letter.operations.send.id)
        }
        if losesAnswers { throw URLError(.timedOut) }
        return letters[letter.id]
    }

    func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
    func delete(id: UUID, operation: SyncClientOperation) async throws {}
    func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage { MailPage() }
    func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions { MailDeliveryOptions() }
    // swiftlint:enable async_without_await
}

/// Changing a letter that was sent and has not arrived, with the real file cache in a temporary
/// folder and a fake server that answers as `send_letter` and `edit_letter` do.
@MainActor
struct LetterChangeTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let owner = UUID()
    private let couple = UUID()

    private final class Operations: SyncClientOperationProviding {
        func makeOperation() -> SyncClientOperation {
            SyncClientOperation(clientID: UUID(), clientSequence: 1)
        }
    }

    private func composer(_ server: Post) async -> LetterComposer {
        let composer = LetterComposer(
            cache: FileMailCache(directoryURL: directory), gateway: server, operationProvider: Operations()
        )
        await composer.load(ownerUserID: owner)
        return composer
    }

    private func onItsWay(photo: UUID? = UUID()) -> Letter {
        Letter(
            id: UUID(), authorUserID: owner, recipientUserID: UUID(), templateKey: .goodNight, body: "Sleep well.",
            mediaAssetID: photo, deliveryKind: .at, deliverAt: .now.addingTimeInterval(86_400), state: .sealed,
            deliveredAt: nil, openedAt: nil, createdAt: .now
        )
    }

    @Test func aChangeNeverTakesThePlaceOfALetterBeingWritten() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        let composer = await composer(server)
        composer.choose(LetterTemplate(.missYou))
        composer.updateBody("Three more weeks and")

        #expect(!composer.startChange(of: letter))
        await composer.load(ownerUserID: owner)
        let reopened = await self.composer(server)
        #expect(reopened.draft?.content.body == "Three more weeks and")
        #expect(reopened.draft?.changing == nil)

        reopened.discard()
        #expect(reopened.startChange(of: letter))
        #expect(reopened.startChange(of: letter))
        #expect(!reopened.startChange(of: onItsWay()))
        await reopened.load(ownerUserID: owner)
        let changing = await self.composer(server)
        #expect(changing.draft?.changing == letter.id)
        #expect(changing.draft?.content.body == "Sleep well.")
        #expect(changing.draft?.content.storedPhotoID == letter.mediaAssetID)
    }

    @Test func aSavedChangeReplacesTheLetterUnderItsIDAndKeepsItsPhoto() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        await server.put(letter)
        let composer = await composer(server)
        #expect(composer.startChange(of: letter))
        composer.updateBody("Sleep well. See you Friday.")

        guard case let .sent(saved?) = await composer.send(coupleID: couple) else {
            Issue.record("expected the change to land")
            return
        }
        #expect(saved.id == letter.id)
        #expect(saved.body == "Sleep well. See you Friday.")
        #expect(saved.mediaAssetID == letter.mediaAssetID)
        #expect(await server.sends.isEmpty)
        #expect(composer.draft == nil)
        #expect(composer.sentLetterID == letter.id)
    }

    @Test func aChangeThatReachesTheServerAfterTheLetterArrivedStaysAsANewLetter() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        await server.put(letter)
        let composer = await composer(server)
        #expect(composer.startChange(of: letter))
        composer.updateBody("Sleep well. See you Friday.")
        await server.arrive(letter.id)

        // The kept photo stays with the letter that arrived, and the notice says so.
        #expect(await composer.send(coupleID: couple) == .notChanged(.changeTooLatePhotoStays))
        #expect(composer.draft?.content.body == "Sleep well. See you Friday.")
        #expect(composer.draft?.changing == nil)
        #expect(composer.draft?.pendingSend == nil)
        #expect(composer.draft?.content.storedPhotoID == nil)
        #expect(await server.letters[letter.id]?.body == "Sleep well.")

        #expect(await composer.send(coupleID: couple) == .sent(nil))
        let sends = await server.sends
        #expect(sends.count == 1)
        #expect(sends.first?.id != letter.id)
        #expect(sends.first?.content.trimmedBody == "Sleep well. See you Friday.")
    }

    @Test func aChangeRetriedAfterTheAppClosedLandsOnceThoughTheLetterArrivedMeanwhile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        await server.put(letter)
        let first = await composer(server)
        #expect(first.startChange(of: letter))
        first.updateBody("Sleep well. See you Friday.")
        await server.loseAnswers(true)
        guard case .failed = await first.send(coupleID: couple) else {
            Issue.record("expected the lost answer to fail")
            return
        }
        #expect(first.draft?.pendingSend != nil)

        await server.arrive(letter.id)
        await server.loseAnswers(false)
        await first.load(ownerUserID: owner)
        let reopened = await composer(server)
        #expect(reopened.draft?.unconfirmed == true)
        guard case let .sent(saved?) = await reopened.send(coupleID: couple) else {
            Issue.record("expected the replay to say the change landed")
            return
        }
        #expect(saved.body == "Sleep well. See you Friday.")
        #expect(reopened.draft == nil)
        let changes = await server.changes
        try #require(changes.count == 2)
        #expect(changes[1].operations == changes[0].operations)
    }

    @Test func aChangeMadeOfflineIsKeptAndTheAuthorIsTold() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        await server.put(letter)
        await server.goOffline(true)
        let composer = await composer(server)
        #expect(composer.startChange(of: letter))
        composer.updateBody("Sleep well. See you Friday.")

        #expect(await composer.send(coupleID: couple) == .failed(.changeOffline))
        #expect(composer.draft?.changing == letter.id)
        #expect(composer.draft?.content.body == "Sleep well. See you Friday.")
        #expect(await server.letters[letter.id]?.body == "Sleep well.")
        await composer.load(ownerUserID: owner)
        let reopened = await self.composer(server)
        #expect(reopened.draft?.content.body == "Sleep well. See you Friday.")
    }

    @Test func aLetterThatArrivesWhileItIsBeingChangedEndsTheChangeAndKeepsTheWords() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        let composer = await composer(server)
        #expect(composer.startChange(of: letter))
        composer.updateBody("Sleep well. See you Friday.")
        #expect(composer.settleChange([letter]) == .ignored)

        var arrived = letter
        arrived.state = .delivered
        #expect(composer.settleChange([arrived]) == .notChanged(.changeTooLatePhotoStays))
        #expect(composer.draft?.changing == nil)
        #expect(composer.draft?.content.body == "Sleep well. See you Friday.")
        #expect(composer.settleChange([arrived]) == .ignored)
    }

    @Test func aBirthdayCardStartsOnTheBirthdayUntilTheAuthorPicks() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-10T20:00:00Z"))
        let birthday = LetterDelivery.at(try #require(ISO8601DateFormatter().date(from: "2026-11-19T23:00:00Z")))
        let composer = await composer(server)
        composer.choose(LetterTemplate(.birthday))
        composer.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: nil, now: now)
        #expect(composer.draft?.content.delivery == .now)
        composer.suggestDelivery(partnerBirthday: nil, timeZone: tokyo, now: now)
        #expect(composer.draft?.content.delivery == .now)
        composer.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: tokyo, now: now)
        #expect(composer.draft?.content.delivery == birthday)
        #expect(composer.draft?.birthdayArrival != nil)

        composer.choose(LetterTemplate(.missYou))
        composer.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: tokyo, now: now)
        #expect(composer.draft?.content.delivery == .now)
        composer.choose(LetterTemplate(.birthday))
        composer.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: tokyo, now: now)

        await composer.load(ownerUserID: owner)
        let reopened = await self.composer(server)
        #expect(reopened.draft?.content.delivery == birthday)
        reopened.updateDelivery(.now)
        reopened.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: tokyo, now: now)
        reopened.choose(LetterTemplate(.missYou))
        reopened.choose(LetterTemplate(.birthday))
        reopened.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: tokyo, now: now)
        #expect(reopened.draft?.content.delivery == .now)
        #expect(reopened.draft?.birthdayArrival == nil)

        reopened.updateDelivery(.together)
        reopened.choose(LetterTemplate(.missYou))
        reopened.choose(LetterTemplate(.birthday))
        reopened.suggestDelivery(partnerBirthday: "1998-11-20", timeZone: tokyo, now: now)
        #expect(reopened.draft?.content.delivery == .together)
    }

    @Test func aLetterForTheNextMeetingIsChangedAsOneThatKeepsWaiting() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        var letter = onItsWay()
        letter = Letter(
            id: letter.id, authorUserID: owner, recipientUserID: letter.recipientUserID, templateKey: .goodNight,
            body: "Sleep well.", mediaAssetID: nil, deliveryKind: .together, deliverAt: nil, state: .sealed,
            deliveredAt: nil, openedAt: nil, createdAt: .now
        )
        await server.put(letter)
        let composer = await composer(server)
        #expect(composer.startChange(of: letter))
        #expect(composer.draft?.content.delivery == .together)
        #expect(composer.draft?.deliveryIsChosen == true)
        composer.updateBody("See you at the station.")
        guard case let .sent(saved?) = await composer.send(coupleID: couple) else {
            Issue.record("expected the change to land")
            return
        }
        #expect(saved.deliveryKind == .together)
        #expect(saved.body == "See you at the station.")
    }

    @Test func aMoveToTheNextMeetingTheServerRefusesKeepsTheChange() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Post()
        let letter = onItsWay()
        await server.put(letter)
        await server.refuseMeeting(true)
        let composer = await composer(server)
        #expect(composer.startChange(of: letter))
        composer.updateBody("Sleep well. See you Friday.")
        composer.updateDelivery(.together)

        #expect(await composer.send(coupleID: couple) == .failed(.changeMeetingUnavailable))
        #expect(composer.draft?.changing == letter.id)
        #expect(composer.draft?.content.body == "Sleep well. See you Friday.")
        #expect(await server.letters[letter.id]?.deliveryKind == .at)
    }
}

/// Mail's side of a change: the Sent list and the photos this phone keeps.
@MainActor
struct MailChangeTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let me = UUID()

    /// Changes a letter as `edit_letter` does, keeping the photo the change names.
    private actor Server: MailGateway {
        // swiftlint:disable async_without_await
        func change(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
            Letter(
                id: letter.id, authorUserID: UUID(), recipientUserID: UUID(),
                templateKey: letter.content.templateKey, body: letter.content.trimmedBody,
                mediaAssetID: letter.content.storedPhotoID, deliveryKind: .at,
                deliverAt: .now.addingTimeInterval(86_400), state: .sealed, deliveredAt: nil, openedAt: nil,
                createdAt: .now
            )
        }

        func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? { nil }
        func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
        func delete(id: UUID, operation: SyncClientOperation) async throws {}
        func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage { MailPage() }
        func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions { MailDeliveryOptions() }
        // swiftlint:enable async_without_await
    }

    private actor Evictions {
        private(set) var ids: [UUID] = []
        func add(_ evicted: [UUID]) { ids += evicted }
    }

    @Test func aRemovedPhotoLeavesThePhoneAndAnotherLetterBeingWrittenStays() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = UUID()
        let letter = Letter(
            id: UUID(), authorUserID: me, recipientUserID: UUID(), templateKey: .goodNight, body: "Sleep well.",
            mediaAssetID: photo, deliveryKind: .at, deliverAt: .now.addingTimeInterval(86_400), state: .sealed,
            deliveredAt: nil, openedAt: nil, createdAt: .now
        )
        let cache = FileMailCache(directoryURL: directory)
        await cache.save(MailSnapshot(sent: MailPage(letters: [letter])), ownerUserID: me)
        let evictions = Evictions()
        let mail = MailViewModel(cache: cache, gateway: Server(), evictPhotos: { await evictions.add($0) })
        await mail.configure(ownerUserID: me, coupleID: UUID())

        mail.composer.choose(LetterTemplate(.missYou))
        #expect(!mail.change(letter))
        #expect(mail.notice?.error == .finishOtherLetterFirst)
        #expect(mail.composer.draft?.content.templateKey == .missYou)

        mail.composer.discard()
        #expect(mail.change(letter))
        mail.composer.removePhoto()
        mail.composer.updateBody("Sleep well. See you Friday.")
        await mail.send()

        #expect(mail.sent.map(\.body) == ["Sleep well. See you Friday."])
        #expect(mail.sent.first?.mediaAssetID == nil)
        #expect(await evictions.ids == [photo])
    }

    @Test func aLetterThatWaitsForTheNextMeetingKeepsThatChoiceWithoutANewCheck() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let waiting = Letter(
            id: UUID(), authorUserID: me, recipientUserID: UUID(), templateKey: .goodNight, body: "Sleep well.",
            mediaAssetID: nil, deliveryKind: .together, deliverAt: nil, state: .sealed,
            deliveredAt: nil, openedAt: nil, createdAt: .now
        )
        let timed = Letter(
            id: UUID(), authorUserID: me, recipientUserID: UUID(), templateKey: .goodNight, body: "Sleep well.",
            mediaAssetID: nil, deliveryKind: .at, deliverAt: .now.addingTimeInterval(86_400), state: .sealed,
            deliveredAt: nil, openedAt: nil, createdAt: .now
        )
        let cache = FileMailCache(directoryURL: directory)
        await cache.save(MailSnapshot(sent: MailPage(letters: [waiting, timed])), ownerUserID: me)
        let mail = MailViewModel(cache: cache, gateway: Server(), evictPhotos: { _ in })
        await mail.configure(ownerUserID: me, coupleID: UUID())

        #expect(!mail.keepsMeeting)
        #expect(mail.change(waiting))
        #expect(mail.keepsMeeting)
        mail.composer.discard()
        #expect(mail.change(timed))
        #expect(!mail.keepsMeeting)

        // After a relaunch the letter may be on no loaded list, and the change still keeps the meeting.
        mail.composer.discard()
        #expect(mail.change(waiting))
        await mail.composer.load(ownerUserID: me)
        await cache.save(MailSnapshot(), ownerUserID: me)
        let relaunched = MailViewModel(cache: cache, gateway: Server(), evictPhotos: { _ in })
        await relaunched.configure(ownerUserID: me, coupleID: UUID())
        #expect(relaunched.sent.isEmpty)
        #expect(relaunched.keepsMeeting)
    }
}
