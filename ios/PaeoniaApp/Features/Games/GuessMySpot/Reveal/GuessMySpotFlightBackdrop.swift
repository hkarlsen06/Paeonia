import MapKit
import SwiftUI

/// The zoom out's pictures lined up with the map as it zooms out, each closer one
/// over the wider ones so the picture is as sharp as it can be, everywhere but
/// where the map already has its images. A zoom out shows gray where the map's
/// images of the wider view are still loading, which takes longer than the zoom
/// out even when they are on the phone. The pictures cover that gray. They are
/// over the map's pins and line too, so the line starts drawing once they have faded.
struct GuessMySpotFlightBackdrop: View {
    /// The zoom out's views, drawn ahead by the preloader, from the widest to the
    /// closest, and the part of the map the camera had loaded when the zoom out began.
    struct Pictures {
        let pictures: [GuessMySpotMapPreloader.Picture]
        let loaded: MKMapRect
        var opacity: Double = 1
    }

    let pictures: Pictures
    /// Where the camera is now, over the map's frame.
    let view: MKMapRect
    /// How big the map draws, past its frame at the bottom.
    let size: CGSize

    var body: some View {
        let loaded = onScreen(pictures.loaded)
        ZStack(alignment: .topLeading) {
            ForEach(pictures.pictures.indices, id: \.self) { index in
                let picture = pictures.pictures[index], frame = onScreen(picture.rect)
                Image(uiImage: picture.image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        // The pictures are blown up until the zoom out ends, labels and all. Soft, they read as motion.
        .blur(radius: 4, opaque: true)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask {
            Rectangle()
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: loaded.width, height: loaded.height)
                        .offset(x: loaded.minX, y: loaded.minY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
        .clipped()
        .opacity(pictures.opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func onScreen(_ rect: MKMapRect) -> CGRect {
        let scale = size.width / max(1, view.width)
        return CGRect(
            x: (rect.minX - view.minX) * scale,
            y: (rect.minY - view.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
