import Foundation

/// A photo or video picked for the draft. The id stays the same for the life of the item,
/// so comparing drafts and keying thumbnails never has to compare the bytes.
struct MemoryDraftMedia: Identifiable, Equatable, Sendable {
    enum Content: Sendable {
        case photo(Data)
        /// A video ready to send. Its file stays in `videoDirectoryURL()` until the memory
        /// is saved or the draft is thrown away, and never goes into the draft's JSON.
        case video(PreparedVideo)
    }

    let id: UUID
    let content: Content
    var accessibilityText: String = ""

    init(id: UUID = UUID(), content: Content, accessibilityText: String = "") {
        self.id = id
        self.content = content
        self.accessibilityText = accessibilityText
    }

    static func photos(_ data: [Data]) -> [Self] {
        data.map { Self(content: .photo($0)) }
    }

    var photoData: Data? {
        if case .photo(let data) = content { data } else { nil }
    }

    var video: PreparedVideo? {
        if case .video(let video) = content { video } else { nil }
    }

    /// Description edits must also trigger draft persistence.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.accessibilityText == rhs.accessibilityText
    }

    /// Where picked videos wait. The privacy purge deletes the whole outgoing folder.
    nonisolated static func videoDirectoryURL() -> URL {
        PreparedVideo.outgoingMediaDirectoryURL().appendingPathComponent("memories", isDirectory: true)
    }

    /// Deletes the files of the videos in `media`, once they are sent or thrown away.
    static func deleteVideoFiles(of media: [Self]) {
        for video in media.compactMap(\.video) {
            try? FileManager.default.removeItem(at: video.fileURL)
        }
    }
}

/// The in-progress contents of the new-memory form. Held by the memories view model and
/// saved on the device, not by the sheet, so dismissing the sheet (including an
/// accidental swipe-down while reaching for the keyboard) keeps the work. Reopening
/// restores it; a successful save (or a deliberate Cancel) resets it.
struct MemoryDraft: Equatable {
    var existingDescriptions: [UUID: String] = [:]
    var title: String = ""
    var date: Date = Date()
    var note: String = ""
    var media: [MemoryDraftMedia] = []
    var place: MemoryPlace?
    var visitID: UUID?

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && media.isEmpty
            && place == nil
    }

    /// The written parts, for copying out when the memory can no longer be saved.
    var copyableText: String {
        ([title, note] + media.map(\.accessibilityText) + Array(existingDescriptions.values))
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

    /// The durable part of an edit. New photo and video picks remain unsaved until attached.
    func savedBaseline(from record: MemoryRecord) -> MemoryDraft {
        var baseline = MemoryDraft(
            title: record.snapshot.title ?? "",
            date: MemoryTimeline.pickerDate(forLocalDate: record.snapshot.memoryDate) ?? record.snapshot.createdAt,
            note: record.snapshot.ownNote?.visibleBody ?? "",
            media: [],
            place: record.snapshot.place
        )
        baseline.existingDescriptions = existingDescriptions.reduce(into: [:]) { result, entry in
            result[entry.key] = record.snapshot.media.first { $0.mediaAssetID == entry.key }?.accessibilityText
        }
        return baseline
    }
}
