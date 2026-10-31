import Foundation

/// The in-progress contents of the new-memory form. Held by the memories view model and
/// saved on the device, not by the sheet, so dismissing the sheet (including an
/// accidental swipe-down while reaching for the keyboard) keeps the work. Reopening
/// restores it; a successful save (or a deliberate Cancel) resets it.
/// A photo picked for the draft. The id stays the same for the life of the photo, so
/// comparing drafts and keying thumbnails never has to compare the image bytes.
struct MemoryDraftPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let data: Data
    var accessibilityText: String = ""

    init(id: UUID = UUID(), data: Data, accessibilityText: String = "") {
        self.id = id
        self.data = data
        self.accessibilityText = accessibilityText
    }

    static func photos(_ data: [Data], descriptions: [String]) -> [Self] {
        data.enumerated().map { index, bytes in
            Self(data: bytes, accessibilityText: descriptions.indices.contains(index) ? descriptions[index] : "")
        }
    }

    /// Description edits must also trigger draft persistence.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.accessibilityText == rhs.accessibilityText
    }
}

struct MemoryDraft: Equatable {
    var existingDescriptions: [UUID: String] = [:]
    var title: String = ""
    var date: Date = Date()
    var note: String = ""
    var photos: [MemoryDraftPhoto] = []
    var place: MemoryPlace?

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photos.isEmpty
            && place == nil
    }

    /// The written parts, for copying out when the memory can no longer be saved.
    var copyableText: String {
        ([title, note] + photos.map(\.accessibilityText) + Array(existingDescriptions.values))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
