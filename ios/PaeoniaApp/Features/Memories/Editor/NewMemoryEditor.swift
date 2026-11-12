import SwiftUI

/// The new-memory form on the view model's draft, for the Memories tab and the Us tab's visit
/// photo card. Present it in a sheet that calls `flushDraft()` when it closes. Swipe dismissal
/// waits for draft persistence, and a failed write keeps the form open with its attachments and
/// a retry action.
struct NewMemoryEditor: View {
    let viewModel: MemoriesViewModel
    var visitID: UUID?
    /// The saved draft, shown while the sheet closes. `createMemory` empties the view model's draft
    /// as soon as the memory is saved, so a kept draft can never save the same memory twice.
    @State private var saving: MemoryDraft?

    var body: some View {
        MemoryEditorView(
            draft: Binding(get: { saving ?? viewModel.draft }, set: { viewModel.updateDraft($0) }),
            allowsPhotos: viewModel.canAttachPhotos,
            uploadProgress: viewModel.photoUploadProgress,
            knownPlaces: viewModel.knownPlaces,
            draftFailure: viewModel.draftFailure,
            draftNeedsSaving: viewModel.draftNeedsSaving,
            onRetryDraft: {
                if viewModel.draftFailure == .read {
                    viewModel.restoreDraft()
                } else {
                    viewModel.saveDraftNow()
                }
            },
            onDiscardDraft: { viewModel.discardDraft() }
        ) { title, date, note, photos, _, place in
            saving = viewModel.draft
            let saved = await viewModel.createMemory(
                title: title, date: date, note: note, photos: photos,
                photoDescriptions: viewModel.draft.photos.map(\.accessibilityText), place: place,
                visitID: viewModel.draft.visitLink(forCardOf: visitID)
            )
            if !saved { saving = nil }
            return saved ? .saved : .failed
        }
    }
}
