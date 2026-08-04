import Foundation

/// The edit state behind the profile editor at the top of the Me tab.
///
/// The saved values stay upstream in the session — they can refresh while the tab
/// is open — so this pairs the last known saved profile with whatever the user has
/// changed and derives everything the header needs from the two together.
struct ProfileEditorDraft: Equatable, Sendable {
    /// The saved name, already trimmed. Empty when the account has no name yet.
    let savedName: String
    /// The user's own uploaded photo. Only this one can be removed.
    let customPhotoAssetID: UUID?
    /// The private copy of the sign-in provider's photo. It can be replaced by a
    /// custom photo, but never removed on its own.
    let providerPhotoAssetID: UUID?
    /// What the user has typed, or `nil` while the field still mirrors `savedName`.
    let typedName: String?
    /// A cropped photo waiting to be saved.
    let stagedPhotoData: Data?
    let removesExistingPhoto: Bool

    init(
        savedName: String,
        customPhotoAssetID: UUID? = nil,
        providerPhotoAssetID: UUID? = nil,
        typedName: String? = nil,
        stagedPhotoData: Data? = nil,
        removesExistingPhoto: Bool = false
    ) {
        self.savedName = savedName
        self.customPhotoAssetID = customPhotoAssetID
        self.providerPhotoAssetID = providerPhotoAssetID
        self.typedName = typedName
        self.stagedPhotoData = stagedPhotoData
        self.removesExistingPhoto = removesExistingPhoto
    }

    /// What the name field shows. Until the user types, the field keeps following
    /// the saved name, so a name that finishes loading after the tab appears is not
    /// stuck behind stale field state.
    var name: String {
        typedName ?? savedName
    }

    var validatedName: String? {
        AuthDisplayNamePolicy.validatedSingleName(from: name)
    }

    /// The one-word rule is otherwise invisible: a two-word name would just leave
    /// Save disabled with no explanation.
    var showsSingleWordHint: Bool {
        name.trimmedNonEmpty != nil && validatedName == nil
    }

    var photoUpdate: AuthProfilePhotoUpdate {
        if let stagedPhotoData {
            return .replace(stagedPhotoData)
        }
        if removesExistingPhoto {
            return .remove
        }
        return .unchanged
    }

    /// The stored photo the avatar should fall back to when nothing is staged.
    /// Removing a custom photo reveals the provider photo underneath it.
    var previewPhotoAssetID: UUID? {
        if removesExistingPhoto {
            return providerPhotoAssetID
        }
        return customPhotoAssetID ?? providerPhotoAssetID
    }

    var hasVisiblePhoto: Bool {
        stagedPhotoData != nil || previewPhotoAssetID != nil
    }

    var hasRemovablePhoto: Bool {
        stagedPhotoData != nil || (!removesExistingPhoto && customPhotoAssetID != nil)
    }

    var hasChanges: Bool {
        photoUpdate != .unchanged
            || validatedName != AuthDisplayNamePolicy.validatedSingleName(from: savedName)
    }

    var canSave: Bool {
        hasChanges && validatedName != nil
    }
}
