import Foundation
import Testing
@testable import PaeoniaApp

struct LetterBodyTests {
    @Test func countsCodePointsAfterTrimmingAsTheServerDoes() {
        // "❤️" is the heart and the sign that makes it red, so two code points.
        #expect(LetterBody.length(String(repeating: "❤️", count: 1_000)) == 2_000)
        #expect(LetterBody.canSend(String(repeating: "❤️", count: 1_000)))
        #expect(!LetterBody.canSend(String(repeating: "❤️", count: 1_001)))
        #expect(LetterBody.canSend("  \n" + String(repeating: "a", count: 2_000) + "\u{3000}\t"))
    }

    @Test func trimsWhatJavaScriptTrimsAndNothingElse() {
        #expect(!LetterBody.canSend("\u{FEFF}"))
        #expect(!LetterBody.canSend("\u{2028}\u{00A0}\u{2003}"))
        #expect(LetterBody.trimmed("\u{FEFF} hi \u{FEFF}") == "hi")
        // U+0085 is not white space to JavaScript, so the server keeps it and so does the phone.
        #expect(LetterBody.trimmed("\u{0085}hi") == "\u{0085}hi")
        #expect(LetterBody.canSend("\u{0085}"))
    }

    @Test func cutsALongNoteAtAWholeCharacter() {
        let cut = LetterBody.limited(String(repeating: "❤️", count: 1_200))
        #expect(cut == String(repeating: "❤️", count: 1_000))
        #expect(LetterBody.limited("short") == "short")
    }
}

@MainActor
struct LetterDraftTests {
    private final class Operations: SyncClientOperationProviding {
        func makeOperation() -> SyncClientOperation {
            SyncClientOperation(clientID: UUID(), clientSequence: 1)
        }
    }

    @Test func theServersLetterIsComparedWithWhatTheAuthorWroteNotWithWhenItArrives() {
        let setTime = Date(timeIntervalSince1970: 1_800_000_000)
        var content = LetterContent(templateKey: .missYou, body: " See you. ")
        content.delivery = .at(setTime)
        func stored(_ card: LetterTemplate.Key = .missYou, _ body: String = "See you.", photo: UUID? = nil) -> Letter {
            Letter(
                id: UUID(), authorUserID: UUID(), recipientUserID: UUID(), templateKey: card, body: body,
                mediaAssetID: photo, deliveryKind: .now, deliverAt: setTime.addingTimeInterval(-3_600),
                state: .delivered, deliveredAt: setTime, openedAt: nil, createdAt: setTime
            )
        }

        // The first try went at once, an hour before the time the draft now holds.
        #expect(content.matches(stored()))
        #expect(!content.matches(stored(.goodMorning)))
        #expect(!content.matches(stored(.missYou, "See you soon.")))
        #expect(!content.matches(stored(photo: UUID())))
    }

    @Test func aDraftThatStartedASendKeepsItsLetterIDAndRenewsOnlyChangedOperations() {
        let operations = Operations()
        var draft = LetterDraft(content: LetterContent(templateKey: .missYou, body: "I miss you."))
        let first = draft.nextSend(makeOperation: operations.makeOperation)
        draft.pendingSend = first
        #expect(draft.nextSend(makeOperation: operations.makeOperation) == first)

        draft.content.body = "I miss you so much."
        let edited = draft.nextSend(makeOperation: operations.makeOperation)
        #expect(edited.id == first.id)
        #expect(edited.operations.send != first.operations.send)
        #expect(edited.operations.reserve == first.operations.reserve)

        draft.content.photo = LetterPhoto(id: UUID(), mimeType: "image/jpeg", fileExtension: "jpg", width: 4, height: 3)
        let withPhoto = draft.nextSend(makeOperation: operations.makeOperation)
        #expect(withPhoto.id == first.id)
        #expect(withPhoto.operations.reserve != first.operations.reserve)
        #expect(withPhoto.operations.finalize != first.operations.finalize)

        draft.pendingSend = nil
        #expect(draft.nextSend(makeOperation: operations.makeOperation).id != first.id)
    }
}

struct LetterDeliveryTests {
    private func morning(after iso: String, in zone: String) throws -> String {
        let now = try #require(ISO8601DateFormatter().date(from: iso))
        let timeZone = try #require(TimeZone(identifier: zone))
        return ISO8601DateFormatter().string(from: LetterDelivery.nextMorning(after: now, in: timeZone))
    }

    @Test func isThePartnersNext0800AsTheServerWorksItOut() throws {
        #expect(try morning(after: "2026-11-10T20:00:00Z", in: "Asia/Tokyo") == "2026-11-10T23:00:00Z")
        #expect(try morning(after: "2026-11-10T20:00:00Z", in: "America/Los_Angeles") == "2026-11-11T16:00:00Z")
        #expect(try morning(after: "2026-11-10T20:00:00Z", in: "Europe/Oslo") == "2026-11-11T07:00:00Z")
        #expect(try morning(after: "2026-11-11T07:00:00Z", in: "Europe/Oslo") == "2026-11-12T07:00:00Z")
    }

    @Test func followsTheClocksAcrossDaylightSavingChanges() throws {
        #expect(try morning(after: "2026-03-28T22:00:00Z", in: "Europe/Oslo") == "2026-03-29T06:00:00Z")
        #expect(try morning(after: "2026-10-24T22:00:00Z", in: "Europe/Oslo") == "2026-10-25T07:00:00Z")
        #expect(try morning(after: "2026-11-01T03:00:00Z", in: "America/New_York") == "2026-11-01T13:00:00Z")
    }
}

struct MailTimelineMergeTests {
    private let me = UUID(), partner = UUID()

    private func letter(_ minute: Int) -> Letter {
        let at = Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60)
        return Letter(
            id: UUID(), authorUserID: partner, recipientUserID: me, templateKey: .blank, body: "\(minute)",
            mediaAssetID: nil, deliveryKind: nil, deliverAt: nil, state: .opened, deliveredAt: at, openedAt: at,
            createdAt: at
        )
    }

    private func cursor(_ letter: Letter) -> LetterCursor {
        LetterCursor(at: "\(letter.id)", id: letter.id)
    }

    @Test func aNewPageKeepsTheOlderLettersAlreadyLoadedWithNoHole() {
        let letters = Array((0..<6).map(letter).reversed())
        let shown = MailPage(letters: letters, nextBefore: cursor(letters[5]))
        let newer = letter(10)
        let page = MailPage(letters: [newer, letters[0], letters[1]], nextBefore: cursor(letters[1]))

        let merged = MailTimeline.merged(page, keeping: shown, in: .received)

        #expect(merged.letters.map(\.id) == ([newer] + letters).map(\.id))
        #expect(merged.nextBefore == shown.nextBefore)
    }

    @Test func aPageThatSharesNoLetterStartsTheListAgain() {
        let shown = MailPage(letters: [letter(1), letter(0)], nextBefore: nil)
        let page = MailPage(letters: [letter(9), letter(8)], nextBefore: LetterCursor(at: "x", id: UUID()))
        #expect(MailTimeline.merged(page, keeping: shown, in: .received) == page)
    }

    @Test func aDeletedLetterLeavesWithTheNextPage() {
        let letters = [letter(3), letter(2), letter(1)]
        let shown = MailPage(letters: letters, nextBefore: nil)
        let page = MailPage(letters: [letters[0], letters[2]], nextBefore: nil)
        #expect(MailTimeline.merged(page, keeping: shown, in: .received) == page)
    }
}
