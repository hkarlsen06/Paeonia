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
    var visitID: UUID?

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

extension MemoryDraft {
    /// Fields the person left alone follow the saved copy when an edit partly succeeds.
    /// Otherwise a retry against the new baseline would overwrite a partner's change.
    mutating func rebaseUntouchedFields(from base: MemoryRecord, to saved: MemoryRecord) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines) == (base.snapshot.title ?? "") {
            title = saved.snapshot.title ?? ""
        }
        if MemoryTimeline.localDateString(for: date) == base.snapshot.memoryDate {
            date = MemoryTimeline.pickerDate(forLocalDate: saved.snapshot.memoryDate) ?? date
        }
        if note.trimmingCharacters(in: .whitespacesAndNewlines) == (base.snapshot.ownNote?.visibleBody ?? "") {
            note = saved.snapshot.ownNote?.visibleBody ?? ""
        }
        if place == base.snapshot.place { place = saved.snapshot.place }
    }

    func visitLink(forCardOf cardVisitID: UUID?) -> UUID? {
        cardVisitID != nil && visitID == cardVisitID ? cardVisitID : nil
    }

    /// Moves the form onto the memory this one joined. When the form's title differs from the
    /// joined memory's, it goes on the first line of the note. Returns whether it did.
    mutating func follow(_ joined: MemoryRecord) -> Bool {
        let movesTitle = VisitMemoryJoin.note(title: title, body: nil, joinedTitle: joined.snapshot.title) != nil
        note = VisitMemoryJoin.note(title: title, body: note, joinedTitle: joined.snapshot.title) ?? ""
        title = joined.snapshot.title ?? ""
        date = MemoryTimeline.pickerDate(forLocalDate: joined.snapshot.memoryDate) ?? date
        place = joined.snapshot.place
        return movesTitle
    }

    /// The durable part of an edit. New photo picks remain unsaved until attached.
    func savedBaseline(from record: MemoryRecord) -> MemoryDraft {
        var baseline = MemoryDraft(
            title: record.snapshot.title ?? "",
            date: MemoryTimeline.pickerDate(forLocalDate: record.snapshot.memoryDate) ?? record.snapshot.createdAt,
            note: record.snapshot.ownNote?.visibleBody ?? "",
            photos: [],
            place: record.snapshot.place
        )
        baseline.existingDescriptions = existingDescriptions.reduce(into: [:]) { result, entry in
            result[entry.key] = record.snapshot.media.first { $0.mediaAssetID == entry.key }?.accessibilityText
        }
        return baseline
    }
}
