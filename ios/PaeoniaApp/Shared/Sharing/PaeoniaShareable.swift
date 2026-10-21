import SwiftUI

/// An encoded picture that is ready to share or save.
struct PaeoniaShareImage {
    enum Format {
        case png
        case jpeg
    }

    let data: Data
    let format: Format
}

/// Something a person can send out of the app or keep in Photos: a drawing, a
/// creature, a story card or a story photo. Every surface describes what it
/// shows with one of these, and `PaeoniaShareSheet` does the rest, so sharing and
/// saving look and behave the same everywhere.
struct PaeoniaShareable: Identifiable {
    let id = UUID()
    /// Names the picture in the share sheet and as a file.
    let title: String
    /// A plain-text version that goes with the picture, such as the words of a
    /// story. The sheet offers it as a second way to share.
    var text: String?
    /// False when the person may keep the picture on their phone but not send it
    /// on, such as a story their partner made for them.
    var allowsSharing = true
    /// Makes the picture. The sheet calls it when it opens, so a surface can load
    /// a download or draw a card here. A nil result shows "Try again".
    let makeImage: @MainActor () async -> PaeoniaShareImage?

    init(
        title: String,
        text: String? = nil,
        allowsSharing: Bool = true,
        makeImage: @escaping @MainActor () async -> PaeoniaShareImage?
    ) {
        self.title = title
        self.text = text
        self.allowsSharing = allowsSharing
        self.makeImage = makeImage
    }

    /// What the button that opens the sheet says.
    var actionTitle: LocalizedStringResource {
        allowsSharing ? .commonShare : .shareSave
    }

    var actionSymbol: String {
        allowsSharing ? "square.and.arrow.up" : "square.and.arrow.down"
    }
}
