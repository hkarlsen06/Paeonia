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

    init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }

    /// The bytes for an id never change, so the id alone decides equality.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct MemoryDraft: Equatable {
    var title: String = ""
    var date: Date = Date()
    var note: String = ""
    var photos: [MemoryDraftPhoto] = []

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photos.isEmpty
    }

    /// The written parts, for copying out when the memory can no longer be saved.
    var copyableText: String {
        [title, note]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
