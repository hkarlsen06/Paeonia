import Foundation
import Testing
@testable import PaeoniaApp

extension LocalPrivacyPurgeTests {
    @Test(arguments: everyPurgeScope)
    func everyPurgeRemovesLettersAndOnlyATemporaryHideKeepsTheUnsentOne(scope: LocalPrivacyPurgeScope) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mail = FileMailCache(directoryURL: directory.appendingPathComponent("mail"))
        let owner = UUID(), partner = UUID()
        let letter = Letter(
            id: UUID(), authorUserID: partner, recipientUserID: owner, templateKey: .missYou,
            body: "Meet me under the clock tower", mediaAssetID: UUID(), deliveryKind: nil, deliverAt: nil,
            state: .opened, deliveredAt: .now, openedAt: .now, createdAt: .now
        )
        await mail.save(MailSnapshot(received: MailPage(letters: [letter])), ownerUserID: owner)
        var content = LetterContent(templateKey: .goodNight, body: "Sleep well.")
        content.photo = LetterPhoto(id: UUID(), mimeType: "image/jpeg", fileExtension: "jpg", width: 4, height: 3)
        let draft = LetterDraft(content: content)
        let photoID = try #require(content.photo?.id)
        #expect(await mail.saveDraftPhoto(Data("unsent photo".utf8), id: photoID, ownerUserID: owner, ifGeneration: 0))
        #expect(await mail.saveDraft(draft, ownerUserID: owner, ifGeneration: 0))
        let fixture = try LivePurgeFixture(widgetCanvas: WidgetCanvasTestEnvironment().makeService(),
                                           memoryMediaURL: directory.appendingPathComponent("memory"),
                                           mailCache: mail)

        #expect(await fixture.purger.purge(ownerUserID: owner, scope: scope) == .completed)

        #expect(await mail.snapshot(ownerUserID: owner) == MailSnapshot())
        if scope == .relationshipAccessHidden {
            #expect(await mail.storedDraft(ownerUserID: owner).draft == draft)
            #expect(await mail.storedDraft(ownerUserID: owner).photo == Data("unsent photo".utf8))
        } else {
            let stored = await mail.storedDraft(ownerUserID: owner)
            #expect(stored.draft == nil)
            #expect(stored.photo == nil)
            // A write made from the draft read before the purge does not bring it back.
            #expect(await !mail.saveDraft(draft, ownerUserID: owner, ifGeneration: 0))
            #expect(await mail.storedDraft(ownerUserID: owner).draft == nil)
        }
    }
}
