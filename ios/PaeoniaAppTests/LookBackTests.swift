import Foundation
import Testing
@testable import PaeoniaApp

// MARK: - Decoding and destinations

struct LookBackItemTests {
    @Test func decodesAQuestionRound() throws {
        let json = """
        {
          "kind": "question",
          "content_date": "2025-10-14",
          "on_this_day": true,
          "question": {
            "instance_id": "11110000-0000-0000-0000-000000000000",
            "short_prompt_en": "A small moment",
            "short_prompt_nb": "Et lite øyeblikk",
            "own_answer": {
              "user_id": "aaaa0000-0000-0000-0000-000000000000",
              "text": "The walk home", "selected_user_id": null, "has_photo": false, "has_voice": false
            },
            "partner_answer": {
              "user_id": "cccc0000-0000-0000-0000-000000000000",
              "text": null, "selected_user_id": null, "has_photo": true, "has_voice": false
            }
          },
          "drawing": null,
          "memory": null
        }
        """
        let item = try JSONDecoder().decode(LookBackItem.self, from: Data(json.utf8))
        #expect(item.kind == .question)
        #expect(item.onThisDay)
        // swiftlint:disable:next number_separator
        #expect(item.contentYear == 2025)
        #expect(item.destination == .questionChat(instanceID: LookBackIDs.instance))
        let question = try #require(item.question)
        #expect(question.shortPrompt(for: Locale(identifier: "nb_NO")) == "Et lite øyeblikk")
        #expect(question.shortPrompt(for: Locale(identifier: "en_US")) == "A small moment")
        #expect(question.ownAnswer.display == .text("The walk home"))
        #expect(question.partnerAnswer.display == .photo)
    }

    @Test func decodesADrawingWithoutACanvasSide() throws {
        let json = """
        {
          "kind": "drawing", "content_date": "2026-09-20", "on_this_day": false,
          "question": null, "memory": null,
          "drawing": {
            "revision_id": "11110000-0000-0000-0000-000000000000",
            "media_asset_id": "33330000-0000-0000-0000-000000000000",
            "author_user_id": "cccc0000-0000-0000-0000-000000000000",
            "canvas_side": null
          }
        }
        """
        let item = try JSONDecoder().decode(LookBackItem.self, from: Data(json.utf8))
        #expect(item.destination == .drawingHistory)
        #expect(item.drawing?.canvasSide == nil)
        #expect(item.drawing?.authorUserID == LookBackIDs.partner)
    }

    @Test func aMemoryOpensItsDetail() {
        #expect(lookBackMemoryItem().destination == .memory(id: LookBackIDs.memory))
    }

    @Test func aKindWithoutItsContentHasNoDestination() {
        let broken = LookBackItem(
            kind: .question, contentDate: "2026-09-01", onThisDay: false, question: nil, drawing: nil, memory: nil
        )
        #expect(broken.destination == nil)
    }

    @Test func anUnknownKindFailsToDecode() {
        let json = #"{"kind":"song","content_date":"2026-09-01","on_this_day":false}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(LookBackItem.self, from: Data(json.utf8))
        }
    }

    @Test func contentDayIsTheDateAtNoon() throws {
        let day = try #require(lookBackMemoryItem(date: "2026-09-01").contentDay)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: day)
        // swiftlint:disable:next number_separator
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 1 && parts.hour == 12)
        #expect(lookBackMemoryItem(date: "nonsense").contentDay == nil)
    }

    @Test func answersShowWordsFirstThenHowTheyWereGiven() {
        let id = LookBackIDs.user
        #expect(lookBackAnswer(id, text: "  hi  ", photo: true).display == .text("hi"))
        #expect(lookBackAnswer(id, text: "   ", photo: true).display == .photo)
        #expect(lookBackAnswer(id, voice: true).display == .voice)
        #expect(lookBackAnswer(id, photo: true, voice: true).display == .photo)
        #expect(lookBackAnswer(id, picked: LookBackIDs.partner).display == .choice(LookBackIDs.partner))
        #expect(lookBackAnswer(id).display == .none)
    }
}

// MARK: - Cache

struct LookBackCacheTests {
    private func makeCache() -> (FileLookBackCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LookBackCacheTest-\(UUID().uuidString)", isDirectory: true)
        return (FileLookBackCache(directoryURL: dir), dir)
    }

    @Test func savesAndLoadsAnEntry() {
        let (cache, dir) = makeCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = LookBackCacheEntry(coupleID: LookBackIDs.couple, item: lookBackMemoryItem())
        cache.save(entry, ownerUserID: LookBackIDs.user)
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: LookBackIDs.couple) == entry)
    }

    @Test func keepsAnEmptyResult() {
        let (cache, dir) = makeCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        cache.save(LookBackCacheEntry(coupleID: nil, item: nil), ownerUserID: LookBackIDs.user)
        let loaded = cache.load(ownerUserID: LookBackIDs.user, coupleID: nil)
        #expect(loaded != nil)
        #expect(loaded?.item == nil)
    }

    @Test func anotherUserNeverSeesTheEntry() {
        let (cache, dir) = makeCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        cache.save(LookBackCacheEntry(coupleID: nil, item: lookBackMemoryItem()), ownerUserID: LookBackIDs.user)
        #expect(cache.load(ownerUserID: LookBackIDs.otherUser, coupleID: nil) == nil)
    }

    @Test func anEntryForAnotherCoupleIsAMiss() {
        let (cache, dir) = makeCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        cache.save(
            LookBackCacheEntry(coupleID: LookBackIDs.couple, item: lookBackMemoryItem()),
            ownerUserID: LookBackIDs.user
        )
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: LookBackIDs.otherCouple) == nil)
        // An unknown couple on either side still matches, so a cold launch shows the card.
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: nil) != nil)
    }

    @Test func clearAllRemovesEverything() {
        let (cache, dir) = makeCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        cache.save(LookBackCacheEntry(coupleID: nil, item: lookBackMemoryItem()), ownerUserID: LookBackIDs.user)
        cache.clearAll()
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: nil) == nil)
        cache.clearAll()
    }

    @Test func aCorruptFileIsAMiss() throws {
        let (cache, dir) = makeCache()
        defer { try? FileManager.default.removeItem(at: dir) }
        cache.save(LookBackCacheEntry(coupleID: nil, item: lookBackMemoryItem()), ownerUserID: LookBackIDs.user)
        let file = dir.appendingPathComponent(LookBackIDs.user.uuidString.lowercased() + ".json")
        try Data("not json".utf8).write(to: file)
        #expect(cache.load(ownerUserID: LookBackIDs.user, coupleID: nil) == nil)
    }
}
