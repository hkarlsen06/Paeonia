import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct SiriMessageDraftTests {
    @Test func siriDraftPreservesAnUnsentMessageOrPhotoCaption() {
        let draft = SiriMessageDraft(ownerUserID: UUID(), subject: .couple, body: "See you soon")
        let existing = "Our picnic\nBring the blanket! "

        let combined = draft.appending(to: existing)

        #expect(combined.hasPrefix(existing))
        #expect(combined.hasSuffix(draft.body))
        #expect(draft.appending(to: "") == draft.body)
    }

    @Test func emptySiriDraftPreservesExistingText() {
        let draft = SiriMessageDraft(ownerUserID: UUID(), subject: .couple, body: "")
        #expect(draft.appending(to: "Unsent caption") == "Unsent caption")
    }
}
