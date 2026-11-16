import ImageIO
import SwiftUI

/// Plays an animated GIF one frame at a time. Decoding every frame up front costs tens
/// of MB per GIF. It stops when it leaves the screen, and with Reduce Motion on it
/// shows the first frame only.
struct AnimatedImageView: View {
    /// Names the GIF. Each frame redraws the view, and comparing this is cheaper than
    /// comparing `data`.
    let id: String
    let data: Data
    var accessibilityLabel: Text?
    var contentMode: ContentMode = .fill

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGImage?
    @State private var isUnreadable = false

    private struct Playback: Equatable {
        let id: String
        let animates: Bool
    }

    var body: some View {
        Group {
            if let frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isUnreadable {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.paeoniaTextTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(accessibilityLabel ?? Text(verbatim: ""))
        .accessibilityHidden(accessibilityLabel == nil)
        .task(id: Playback(id: id, animates: !reduceMotion)) {
            await play(animates: !reduceMotion)
        }
    }

    private func play(animates: Bool) async {
        isUnreadable = false
        guard animates else {
            frame = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            isUnreadable = frame == nil
            return
        }
        let playback = PlaybackFlag()
        // ImageIO calls the block on the main queue for each frame until `stop` is set.
        let status = CGAnimateImageDataWithBlock(data as CFData, nil) { _, image, stop in
            guard playback.isPlaying else {
                stop.pointee = true
                return
            }
            frame = image
        }
        guard status == noErr else {
            frame = nil
            isUnreadable = true
            return
        }
        // SwiftUI cancels this task when the view leaves the screen or the GIF changes.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3_600))
        }
        playback.isPlaying = false
    }
}

private final class PlaybackFlag {
    var isPlaying = true
}
