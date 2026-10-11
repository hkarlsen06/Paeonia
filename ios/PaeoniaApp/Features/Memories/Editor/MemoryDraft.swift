import Foundation

/// The in-progress contents of the new-memory form. Held by the memories view model and
/// saved on the device, not by the sheet, so dismissing the sheet (including an
/// accidental swipe-down while reaching for the keyboard) keeps the work. Reopening
/// restores it; a successful save (or a deliberate Cancel) resets it.
struct MemoryDraft: Equatable {
    var title: String = ""
    var date: Date = Date()
    var note: String = ""
    var photos: [Data] = []

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
