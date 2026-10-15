import SwiftUI
import UIKit

/// Decodes photo bytes once, off the main thread, and hands the image to `content`.
/// A view body must not call `UIImage(data:)`, because it runs on every change. The
/// copy is capped at the size of a compressed daily photo.
struct DailyDecodedPhoto<Content: View, Failure: View>: View {
    let data: Data
    /// Room kept while decoding, so the layout does not jump when the photo arrives.
    let reservedHeight: CGFloat
    @ViewBuilder let content: (UIImage) -> Content
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                content(image)
            } else if didFail {
                failure()
            } else {
                Color.clear.frame(height: reservedHeight)
            }
        }
        // The bytes themselves are the id. Comparing them is a fast memory compare,
        // and two different photos can share a size and a header.
        .task(id: data) {
            let decoded = await MemoryImageDecoding.downsample(data, maxPixelSize: Int(ImageCompressor.maxDimension))
            guard !Task.isCancelled else { return }
            image = decoded
            didFail = decoded == nil
        }
    }
}
