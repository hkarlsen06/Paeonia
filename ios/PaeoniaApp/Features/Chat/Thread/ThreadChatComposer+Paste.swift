import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// Pasting a GIF or a photo into the message field stages it like a pick. Text pastes
// stay with the field.
//
// This is the one place the chat takes pastes. If SwiftUI's paste destination does not
// reach a focused text field, swap this for a UIKit text view here.
extension View {
    func pastingAttachments(into staging: ThreadChatAttachmentStaging, isEnabled: Bool) -> some View {
        pasteDestination(for: ThreadChatPastedImage.self) { images in
            for image in images {
                staging.addPasted(image.data)
            }
        } validator: { images in
            isEnabled ? images : []
        }
    }
}

/// A pasted GIF or picture. Keyboard GIF apps put `com.compuserve.gif` on the pasteboard
/// next to a still image. The GIF comes first here, or it would arrive still.
nonisolated struct ThreadChatPastedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .gif) { Self(data: $0) }
        DataRepresentation(importedContentType: .image) { Self(data: $0) }
    }
}
