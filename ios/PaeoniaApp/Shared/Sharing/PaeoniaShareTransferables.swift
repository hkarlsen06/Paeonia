import SwiftUI
import UniformTypeIdentifiers

/// A PNG that the system share sheet sends. The data is already made, so the
/// share sheet never has to wait for a download or a render.
struct PaeoniaSharedPNG: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

/// A JPEG that the system share sheet sends, for photos.
struct PaeoniaSharedJPEG: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

/// The share button for a prepared picture. It picks the transferable that
/// matches the picture's format.
struct PaeoniaShareImageLink<Label: View>: View {
    let image: PaeoniaShareImage
    let preview: UIImage
    let title: String
    @ViewBuilder var label: () -> Label

    var body: some View {
        // The preview picture is for the share sheet, which reads the title aloud.
        // swiftlint:disable:next accessibility_label_for_image
        let sharePreview = SharePreview(title, image: Image(uiImage: preview))
        switch image.format {
        case .png:
            ShareLink(
                item: PaeoniaSharedPNG(data: image.data, fileName: title),
                preview: sharePreview,
                label: label
            )
        case .jpeg:
            ShareLink(
                item: PaeoniaSharedJPEG(data: image.data, fileName: title),
                preview: sharePreview,
                label: label
            )
        }
    }
}
