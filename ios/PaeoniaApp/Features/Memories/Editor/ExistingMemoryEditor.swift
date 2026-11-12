import SwiftUI

/// The edit form for a saved memory, for its detail screen and the Us tab's visit photo card.
/// It starts from `record`, the memory as it was when the form opened, so saving sends only
/// what the person changed. When the partner deletes the memory meanwhile, the form stays open
/// with the typed text and says why it can't be saved.
struct ExistingMemoryEditor: View {
    let viewModel: MemoriesViewModel
    let currentUserID: UUID?
    /// Called with the memory's id when a save went through whole, before the form closes. After a
    /// join it is the joined memory, which the form follows.
    let onSaved: ((UUID) -> Void)?
    /// What the form compares with. A partial save moves it to the saved copy.
    @State private var base: MemoryRecord
    @State private var draft: MemoryDraft
    @State private var join: MemoryJoinNotice?

    init(
        record: MemoryRecord,
        currentUserID: UUID?,
        viewModel: MemoriesViewModel,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.currentUserID = currentUserID
        self.onSaved = onSaved
        _base = State(initialValue: record)
        _draft = State(
            initialValue: MemoryDraft(
                title: record.snapshot.title ?? "",
                date: MemoryTimeline.pickerDate(forLocalDate: record.snapshot.memoryDate)
                    ?? record.snapshot.createdAt,
                note: record.snapshot.ownNote?.visibleBody ?? "",
                photos: [],
                place: record.snapshot.place
            )
        )
    }

    var body: some View {
        let latest = viewModel.record(for: base.snapshot.memoryID)
        let current = latest ?? base
        MemoryEditorView(
            draft: $draft,
            mode: .edit,
            existingMedia: current.snapshot.media.filter(\.isVisible).sortedForMemoryDisplay(),
            currentUserID: currentUserID,
            hasExistingNote: current.snapshot.ownNote?.visibleBody != nil,
            isMemoryRemoved: latest == nil,
            join: join,
            allowsPhotos: viewModel.canAttachPhotos,
            uploadProgress: viewModel.photoUploadProgress,
            knownPlaces: viewModel.knownPlaces
        ) { title, date, note, photos, removedMedia, place in
            let result = await viewModel.saveEdits(
                MemoryEdit(
                    photoDescriptions: draft.photos.map(\.accessibilityText),
                    existingDescriptions: draft.existingDescriptions,
                    base: base,
                    title: title,
                    date: date,
                    note: note,
                    newPhotos: photos,
                    removedMedia: removedMedia,
                    place: place
                )
            )
            if case .partial(let savedRecord) = result, let savedRecord {
                draft.rebaseUntouchedFields(from: base, to: savedRecord)
                base = savedRecord
            }
            if case .saved = result { onSaved?(base.snapshot.memoryID) }
            return result
        }
        .onChange(of: latest?.snapshot.memoryID) {
            guard let latest, latest.snapshot.memoryID != base.snapshot.memoryID else { return }
            let movedTitle = draft.follow(latest)
            base = latest
            join = MemoryJoinNotice(
                joinedOwnMemory: latest.snapshot.createdByUserID == currentUserID, movedTitle: movedTitle
            )
        }
    }
}

/// What the edit form says after the memory it edits joined another memory for the same visit.
struct MemoryJoinNotice: Equatable {
    /// The memory it joined is the person's own, saved on their other phone.
    let joinedOwnMemory: Bool
    /// The form put the person's title on the first line of their note.
    let movedTitle: Bool

    var message: String {
        let joined = String(localized: joinedOwnMemory ? .memoriesEditorJoinedOwnMessage : .memoriesEditorJoinedMessage)
        return movedTitle ? "\(joined) \(String(localized: .memoriesEditorJoinedTitleMessage))" : joined
    }
}
