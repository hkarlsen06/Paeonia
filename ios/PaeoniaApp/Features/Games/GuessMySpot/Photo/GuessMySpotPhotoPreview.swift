import UIKit

/// The partner's picked photo before it is sent, as the relay brought it: so few
/// pixels that it shows only colors and shapes, and the screens blur it on top.
/// The guesser sees it while the partner checks the photo, and on the guess screen
/// until the real photo loads, which then sharpens out of it.
struct GuessMySpotPhotoPreview: Equatable {
    /// The longest side of the preview the sender makes and the receiver accepts.
    nonisolated static let maxPixelSize = 32
    /// Far above what `maxPixelSize` needs, so a bad message is dropped before decoding.
    nonisolated static let maxBytes = 16_384

    /// The round the photo will make.
    let roundID: UUID
    let image: UIImage

    /// The preview a sending phone puts on the relay, from the prepared photo, which
    /// has no metadata left.
    nonisolated static func jpeg(from photo: Data) async -> Data? {
        let image = await MemoryImageDecoding.downsample(photo, maxPixelSize: maxPixelSize)
        return image?.jpegData(compressionQuality: 0.7)
    }

    /// Reads a preview from the relay. Nil when it is too large to be one.
    init?(roundID: UUID, jpeg: Data) {
        guard jpeg.count <= Self.maxBytes,
              let image = UIImage(data: jpeg),
              max(image.size.width, image.size.height) * image.scale <= CGFloat(Self.maxPixelSize)
        else { return nil }
        self.roundID = roundID
        self.image = image
    }
}
