import Foundation
import Testing
@testable import PaeoniaApp

struct ProfileEditorDraftTests {
    private let customAssetID = UUID()
    private let providerAssetID = UUID()

    @Test func untouchedDraftHasNothingToSave() {
        let draft = ProfileEditorDraft(savedName: "Mina", customPhotoAssetID: customAssetID)

        #expect(draft.name == "Mina")
        #expect(!draft.hasChanges)
        #expect(!draft.canSave)
        #expect(draft.photoUpdate == .unchanged)
        #expect(!draft.showsSingleWordHint)
    }

    /// The field follows the session until the user types, so a name that finishes
    /// loading after the tab appears is not stuck behind stale field state.
    @Test func fieldFollowsSavedNameUntilTheUserTypes() {
        let loading = ProfileEditorDraft(savedName: "")
        #expect(loading.name.isEmpty)

        let loaded = ProfileEditorDraft(savedName: "Mina")
        #expect(loaded.name == "Mina")

        let edited = ProfileEditorDraft(savedName: "Mina", typedName: "Eli")
        #expect(edited.name == "Eli")
        #expect(edited.hasChanges)
        #expect(edited.canSave)
    }

    @Test func retypingTheSameNameIsNotAChange() {
        let draft = ProfileEditorDraft(savedName: "Mina", typedName: "  Mina  ")

        #expect(!draft.hasChanges)
        #expect(!draft.canSave)
    }

    @Test func multiWordNameExplainsItselfAndBlocksSaving() {
        let draft = ProfileEditorDraft(savedName: "Mina", typedName: "Mina Lee")

        #expect(draft.validatedName == nil)
        #expect(draft.showsSingleWordHint)
        #expect(draft.hasChanges)
        #expect(!draft.canSave)
    }

    @Test func emptyNameCannotBeSavedOverAName() {
        let draft = ProfileEditorDraft(savedName: "Mina", typedName: "   ")

        #expect(draft.hasChanges)
        #expect(!draft.canSave)
        // Nothing to explain yet — the placeholder already shows what belongs here.
        #expect(!draft.showsSingleWordHint)
    }

    @Test func stagedPhotoIsSavedAsAReplacement() {
        let data = Data([0x01, 0x02])
        let draft = ProfileEditorDraft(savedName: "Mina", stagedPhotoData: data)

        #expect(draft.photoUpdate == .replace(data))
        #expect(draft.hasChanges)
        #expect(draft.canSave)
        #expect(draft.hasVisiblePhoto)
        #expect(draft.hasRemovablePhoto)
    }

    @Test func onlyTheUsersOwnPhotoCanBeRemoved() {
        let providerOnly = ProfileEditorDraft(
            savedName: "Mina",
            providerPhotoAssetID: providerAssetID
        )
        #expect(providerOnly.hasVisiblePhoto)
        #expect(!providerOnly.hasRemovablePhoto)

        let custom = ProfileEditorDraft(
            savedName: "Mina",
            customPhotoAssetID: customAssetID,
            providerPhotoAssetID: providerAssetID
        )
        #expect(custom.hasRemovablePhoto)
        #expect(custom.previewPhotoAssetID == customAssetID)
    }

    /// Removing a custom photo reveals the sign-in provider photo underneath it
    /// rather than falling back to initials.
    @Test func removingACustomPhotoRevealsTheProviderPhoto() {
        let draft = ProfileEditorDraft(
            savedName: "Mina",
            customPhotoAssetID: customAssetID,
            providerPhotoAssetID: providerAssetID,
            removesExistingPhoto: true
        )

        #expect(draft.previewPhotoAssetID == providerAssetID)
        #expect(draft.photoUpdate == .remove)
        #expect(draft.hasChanges)
        #expect(draft.canSave)
        // Already staged for removal, so there is nothing left to remove.
        #expect(!draft.hasRemovablePhoto)
    }

    @Test func removingTheOnlyPhotoLeavesInitials() {
        let draft = ProfileEditorDraft(
            savedName: "Mina",
            customPhotoAssetID: customAssetID,
            removesExistingPhoto: true
        )

        #expect(draft.previewPhotoAssetID == nil)
        #expect(!draft.hasVisiblePhoto)
    }

    /// A newly picked photo wins over a pending removal, so the user can undo a
    /// removal by choosing a new photo.
    @Test func stagingAPhotoOverridesAPendingRemoval() {
        let data = Data([0x03])
        let draft = ProfileEditorDraft(
            savedName: "Mina",
            customPhotoAssetID: customAssetID,
            stagedPhotoData: data,
            removesExistingPhoto: true
        )

        #expect(draft.photoUpdate == .replace(data))
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
