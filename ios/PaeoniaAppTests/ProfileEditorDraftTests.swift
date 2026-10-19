import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ProfileEditorDraftTests {
    private let customAssetID = UUID()
    private let providerAssetID = UUID()

    @Test func doubleNameCanBeSaved() {
        let draft = ProfileEditorDraft(savedName: "Anne", typedName: "Anne  Marie")

        #expect(draft.validatedName == "Anne Marie")
        #expect(!draft.showsFirstNameHint)
        #expect(draft.canSave)
    }

    @Test func nameWithSurnameExplainsItselfAndBlocksSaving() {
        let draft = ProfileEditorDraft(savedName: "Mina", typedName: "Mina Lee Hansen")

        #expect(draft.validatedName == nil)
        #expect(draft.showsFirstNameHint)
        #expect(draft.hasChanges)
        #expect(!draft.canSave)
    }

    @Test func emptyNameCannotBeSavedOverAName() {
        let draft = ProfileEditorDraft(savedName: "Mina", typedName: "   ")

        #expect(draft.hasChanges)
        #expect(!draft.canSave)
        // Nothing to explain yet — the placeholder already shows what belongs here.
        #expect(!draft.showsFirstNameHint)
    }

    /// Regression guard: a photo-only edit must still be savable while the name is
    /// left exactly as it was.
    @Test func photoOnlyEditIsSavableWithoutTouchingTheName() {
        let draft = ProfileEditorDraft(
            savedName: "Mina",
            customPhotoAssetID: customAssetID,
            typedName: "Mina",
            removesExistingPhoto: true
        )

        #expect(draft.validatedName == "Mina")
        #expect(draft.canSave)
    }
}
