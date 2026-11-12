import Foundation
import Testing
@testable import PaeoniaApp

/// The composer with the real file cache in a temporary folder and a fake server.
@MainActor
struct LetterComposerTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let owner = UUID()
    private let couple = UUID()

    private final class Operations: SyncClientOperationProviding {
        func makeOperation() -> SyncClientOperation {
            SyncClientOperation(clientID: UUID(), clientSequence: 1)
        }
    }

    /// Records each send. While `hangs` is set, a send never hears back, as when the app closes.
    private actor Server: MailGateway {
        private(set) var sends: [LetterSend] = []
        private var hangs: Bool
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(hangs: Bool) {
            self.hangs = hangs
        }

        func answer() {
            hangs = false
            waiting.forEach { $0.resume() }
            waiting = []
        }

        func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
            sends.append(letter)
            if hangs {
                await withCheckedContinuation { waiting.append($0) }
                throw URLError(.networkConnectionLost)
            }
            return nil
        }

        // The protocol's calls go to a server, so they are async even where this fake answers at once.
        // swiftlint:disable async_without_await
        func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
        func delete(id: UUID, operation: SyncClientOperation) async throws {}
        func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage { MailPage() }
        func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions { MailDeliveryOptions() }
        // swiftlint:enable async_without_await
    }

    /// Keeps each letter once by its id, like `send_letter`, and refuses an operation sent again
    /// with another request. While `losesAnswers` is set, it keeps the letter and the answer never arrives.
    private actor Mailroom: MailGateway {
        private(set) var letterIDs: [UUID] = []
        private var requests: [UUID: LetterContent] = [:]
        var losesAnswers = true

        func answerFromNowOn() {
            losesAnswers = false
        }

        // The protocol's calls go to a server, so they are async even where this fake answers at once.
        // swiftlint:disable async_without_await
        func send(_ letter: LetterSend, photo: MemoryUploadMedia?, coupleID: UUID) async throws -> Letter? {
            if let earlier = requests[letter.operations.send.id], earlier != letter.content {
                throw PaeoniaConvexError.server(code: "23505", message: "client operation replay hash mismatch")
            }
            requests[letter.operations.send.id] = letter.content
            if !letterIDs.contains(letter.id) { letterIDs.append(letter.id) }
            if losesAnswers { throw URLError(.networkConnectionLost) }
            return nil
        }

        func open(id: UUID) async throws -> Letter { throw URLError(.badServerResponse) }
        func delete(id: UUID, operation: SyncClientOperation) async throws {}
        func olderLetters(in list: MailboxTab, before: LetterCursor, limit: Int) async throws -> MailPage { MailPage() }
        func deliveryOptions(at now: Date) async throws -> MailDeliveryOptions { MailDeliveryOptions() }
        // swiftlint:enable async_without_await
    }

    private func composer(_ cache: FileMailCache, _ server: any MailGateway) async -> LetterComposer {
        let composer = LetterComposer(cache: cache, gateway: server, operationProvider: Operations())
        await composer.load(ownerUserID: owner)
        return composer
    }

    /// A letter for a set time whose answer was lost, retried after that time passed.
    private func letterSentForATimeThatPassed(_ server: Mailroom) async -> (LetterComposer, later: Date) {
        let composer = await composer(FileMailCache(directoryURL: directory), server)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        composer.choose(LetterTemplate(.goodMorning))
        composer.updateBody("Coffee at the station?")
        composer.updateDelivery(.at(now.addingTimeInterval(60)))
        #expect(await composer.send(coupleID: couple, now: now) == .failed(.sendOffline))
        return (composer, now.addingTimeInterval(120))
    }

    @Test func aRetryAfterTheSetTimePassedSendsTheLetterOnce() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Mailroom()
        let (composer, later) = await letterSentForATimeThatPassed(server)
        await server.answerFromNowOn()

        // The delivery step shows again and moves the passed time forward.
        #expect(composer.moveTimeIfPassed(now: later))
        #expect(await composer.send(coupleID: couple, now: later) == .sent(nil))

        let letterIDs = await server.letterIDs
        #expect(letterIDs.count == 1)
        #expect(composer.draft == nil)
        #expect(composer.sentLetterID == letterIDs.first)
    }

    /// The letter as the first try of `letterSentForATimeThatPassed` stored it.
    private func storedByTheFirstTry(_ id: UUID, setFor time: Date) -> Letter {
        Letter(
            id: id, authorUserID: owner, recipientUserID: UUID(), templateKey: .goodMorning,
            body: "Coffee at the station?", mediaAssetID: nil, deliveryKind: .at, deliverAt: time,
            state: .delivered, deliveredAt: time, openedAt: nil, createdAt: time.addingTimeInterval(-60)
        )
    }

    @Test func aLetterTheServerAlreadyHasIsForgottenThoughTheAppMovedItsTime() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Mailroom()
        let (first, later) = await letterSentForATimeThatPassed(server)
        first.moveTimeIfPassed(now: later)
        // The moved time reaches the phone's storage. Then the app closes and opens again, so
        // nothing in memory says the app moved it.
        await first.load(ownerUserID: owner)
        let composer = await composer(FileMailCache(directoryURL: directory), server)
        #expect(composer.draft?.content.delivery == .at(later.addingTimeInterval(3_600)))

        // The live feed shows the letter in the sent list.
        let letterID = try #require(await server.letterIDs.first)
        let stored = storedByTheFirstTry(letterID, setFor: later.addingTimeInterval(-60))
        #expect(composer.forgetSent([stored]) == .sent(stored))

        #expect(composer.draft == nil)
        #expect(composer.sentLetterID == stored.id)
        await composer.load(ownerUserID: owner)
        #expect(composer.draft == nil)
    }

    @Test func changesMadeAfterTheLetterWentStayAsANewLetter() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Mailroom()
        let (composer, later) = await letterSentForATimeThatPassed(server)
        composer.moveTimeIfPassed(now: later)
        composer.updateBody("Coffee at the station at nine?")

        // The live feed shows the letter in the sent list, as the first try stored it.
        let letterID = try #require(await server.letterIDs.first)
        let stored = storedByTheFirstTry(letterID, setFor: later.addingTimeInterval(-60))
        #expect(composer.forgetSent([stored]) == .sentWithoutLastChanges(stored))

        #expect(composer.draft?.content.trimmedBody == "Coffee at the station at nine?")
        #expect(composer.draft?.pendingSend == nil)
        #expect(composer.sentLetterID == nil)
        // The next Send is a new letter.
        await server.answerFromNowOn()
        #expect(await composer.send(coupleID: couple, now: later) == .sent(nil))
        #expect(await server.letterIDs.count == 2)
        await composer.load(ownerUserID: owner)
        #expect(composer.draft == nil)
    }

    @Test func aSendCutOffWhenTheAppClosedGoesOutAgainAsTheSameLetter() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = Server(hangs: true)
        let first = await composer(FileMailCache(directoryURL: directory), server)
        first.choose(LetterTemplate(.missYou))
        first.updateBody("See you at the station.")
        let cutOff = Task { await first.send(coupleID: couple) }
        var waits = 0
        while await server.sends.isEmpty, waits < 500 {
            waits += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await server.sends.count == 1)

        // The app opens again and reads what the first run stored.
        let reopened = await composer(FileMailCache(directoryURL: directory), server)
        #expect(reopened.draft?.content.trimmedBody == "See you at the station.")
        await server.answer()
        #expect(await reopened.send(coupleID: couple) == .sent(nil))

        let sends = await server.sends
        try #require(sends.count == 2)
        #expect(sends[1].id == sends[0].id)
        #expect(sends[1].operations == sends[0].operations)
        #expect(reopened.draft == nil)
        _ = await cutOff.value
    }

    @Test func changesLandInOrderAndNothingLandsAfterAPurgeOrADiscard() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileMailCache(directoryURL: directory)
        let composer = await composer(cache, Server(hangs: false))
        composer.choose(LetterTemplate(.goodNight))
        for index in 0..<40 {
            composer.updateBody("Sleep well \(index)")
        }
        composer.updateDelivery(.morning)
        await composer.load(ownerUserID: owner)
        #expect(composer.draft?.content.body == "Sleep well 39")
        #expect(composer.draft?.content.delivery == .morning)

        composer.updateBody("Written while the purge runs")
        await cache.clearDrafts()
        composer.updateBody("Written after it")
        await composer.load(ownerUserID: owner)
        #expect(composer.draft == nil)
        #expect(await cache.storedDraft(ownerUserID: owner).draft == nil)

        composer.choose(LetterTemplate(.thankYou))
        composer.updateBody("Thank you")
        composer.discard()
        await composer.load(ownerUserID: owner)
        #expect(composer.draft == nil)
    }
}
