import Foundation

/// What the edit form asks to save. `base` is the memory as it was when the form opened.
struct MemoryEdit {
    var photoDescriptions: [String] = []
    var existingDescriptions: [UUID: String] = [:]
    let base: MemoryRecord
    let title: String
    let date: String
    let note: String
    let newPhotos: [Data]
    let removedMedia: [MemoryMediaSnapshot]
    let place: MemoryPlace?
}

enum MemorySaveResult {
    case saved
    case failed
    case partial(savedRecord: MemoryRecord?)

    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }
}
