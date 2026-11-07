import Observation

@Observable
final class StoryNoteDraft {
    var text: String
    private(set) var savedText: String?

    init(text: String) {
        self.text = text
        savedText = StoriesViewModel.cleanNote(text)
    }

    var canShare: Bool {
        let note = StoriesViewModel.cleanNote(text)
        return note != nil && note != savedText
    }

    /// A successful save can close the editor only while it still shows that version.
    func save(using model: StoriesViewModel, submitting replacement: String? = nil) async -> Bool {
        let shown = text
        let submitted = replacement ?? shown
        let saved = await model.setNote(submitted)
        if saved { savedText = StoriesViewModel.cleanNote(submitted) }
        return saved && text == shown
    }
}
