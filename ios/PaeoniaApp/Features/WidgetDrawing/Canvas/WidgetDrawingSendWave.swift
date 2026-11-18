import DistortionWavesKit
import SwiftUI

/// A sent drawing rises on a wave from the Send button over the screen. The wave
/// plays over a picture of the screen taken at the tap, because the canvas is
/// PencilKit, a UIKit view that SwiftUI cannot pass through the wave's shader.
struct WidgetDrawingSendWave: Identifiable {
    let id = UUID()
    let picture: UIImage
    /// The Send button, in the wave's own coordinates.
    let source: CGRect
    var isRevealed = false

    /// A wave over `area` from `sendButton`, both in window coordinates, or nil
    /// when the screen could not be pictured.
    @MainActor
    init?(area: CGRect, sendButton: CGRect) {
        guard let picture = PaeoniaAppWindow.snapshot(of: area) else { return nil }
        self.picture = picture
        source = sendButton.offsetBy(dx: -area.minX, dy: -area.minY)
    }
}

/// Fills the screen it lays over, reports where that is in the window, and plays
/// `wave` once over it.
struct WidgetDrawingSendWaveLayer: View {
    @Binding var wave: WidgetDrawingSendWave?
    @Binding var area: CGRect

    var body: some View {
        Color.clear
            // Measured inside the safe area it ignores. Measured outside, the frame
            // stops above the home indicator while the picture fills down past it.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area = $0 }
            .overlay {
                if let current = wave {
                    DistortionWave(
                        isRevealed: current.isRevealed,
                        source: current.source,
                        style: Self.style,
                        onFinish: { wave = nil }
                    ) {
                        picture(current)
                    } revealed: {
                        picture(current)
                    }
                    .id(current.id)
                    // The wave starts when this flips, so it mounts at rest first.
                    .onAppear { wave?.isRevealed = true }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
    }

    private func picture(_ wave: WidgetDrawingSendWave) -> some View {
        Image(uiImage: wave.picture)
            .resizable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private static let style: DistortionWaveStyle = {
        var style = DistortionWaveStyle(type: .vertical)
        style.palette = .sunset
        style.cornerRadius = 0
        // The screen takes no touches until the wave ends. The kit's colour and
        // dots linger for 3.6 s; these end it in about 2.3 s.
        style.rimFade = 1.8
        style.hairlineFade = 1.6
        style.particleLife = 1.8
        return style
    }()
}
