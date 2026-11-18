import CoreHaptics
import DistortionWavesKit
import SwiftUI

/// Plays a distortion wave over the whole window, from `source` (a frame in global
/// coordinates). Read it with `@Environment(\.screenWave)`. It does nothing outside
/// `PaeoniaScreenWaveHost`, and nothing under Reduce Motion or VoiceOver. The host sets
/// the style's `cornerRadius` to the window's own, and plays the wave's own haptic with it,
/// so a caller that gets `true` plays no haptic of its own for the same moment.
struct ScreenWaveAction {
    fileprivate var play: (_ source: CGRect, _ style: DistortionWaveStyle) -> Bool = { _, _ in false }

    @discardableResult
    func callAsFunction(from source: CGRect, style: DistortionWaveStyle) -> Bool {
        play(source, style)
    }
}

extension EnvironmentValues {
    @Entry var screenWave = ScreenWaveAction()
}

/// Draws a screen wave over the whole window, bars included. Sits once at the app's root.
/// The wave bends a picture of the window taken when it starts: SwiftUI cannot pass UIKit
/// views such as the PencilKit canvas or the bars through the kit's shaders, and the kit
/// mounts each side several times, so a live screen cannot be one. Nothing under the wave
/// takes touches until it ends. The rules for waves are in the `paeonia-libraries-dev` skill.
struct PaeoniaScreenWaveHost: ViewModifier {
    private struct Run: Identifiable {
        let id = UUID()
        let picture: UIImage
        /// In the host's coordinates.
        let source: CGRect
        let style: DistortionWaveStyle
        var isRevealed = false
    }

    @State private var run: Run?
    /// The whole window, in global coordinates.
    @State private var frame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.screenWave, ScreenWaveAction(play: play))
            .allowsHitTesting(run == nil)
            .overlay {
                Color.clear
                    // Measured inside the safe area it ignores, so it is the window's frame.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
                        // A picture of the old size would stretch, so a resize or a fold ends the wave.
                        if newFrame.size != frame.size { run = nil }
                        frame = newFrame
                    }
                    .overlay {
                        if let run { wave(run) }
                    }
                    .ignoresSafeArea()
            }
    }

    private func wave(_ run: Run) -> some View {
        DistortionWave(
            isRevealed: run.isRevealed,
            source: run.source,
            style: run.style,
            onFinish: { finish(run.id) }
        ) {
            picture(run.picture)
        } revealed: {
            picture(run.picture)
        }
        .id(run.id)
        // The wave starts when this flips, so it mounts at rest first. The haptic starts
        // with it, so its pull and release land on the wave's.
        .onAppear {
            self.run?.isRevealed = true
            ScreenWaveHaptics.play(for: run.style)
        }
        .transition(.opacity)
    }

    private func picture(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func play(from source: CGRect, style: DistortionWaveStyle) -> Bool {
        guard !reduceMotion, !voiceOverEnabled, run == nil,
              let picture = PaeoniaAppWindow.snapshot(of: frame) else { return false }
        var style = style
        style.cornerRadius = PaeoniaAppWindow.cornerRadius
        let run = Run(picture: picture, source: source.offsetBy(dx: -frame.minX, dy: -frame.minY), style: style)
        self.run = run
        // Nothing in the app takes touches until the wave ends, so its end must not hang
        // on the kit's callback alone.
        Task {
            try? await Task.sleep(for: .seconds(style.duration + 1))
            finish(run.id)
        }
        return true
    }

    private func finish(_ id: UUID) {
        guard run?.id == id else { return }
        // The picture still shows the screen as it was at the start. A short fade hands
        // over to the live screen instead of a cut.
        withAnimation(.easeOut(duration: 0.2)) { run = nil }
    }
}

/// The haptic of a screen wave, timed from its style: a soft buzz that tightens while the
/// screen falls toward the source, a sharp tap as the front leaves it, and a buzz that fades
/// as the swell travels out.
private enum ScreenWaveHaptics {
    static func play(for style: DistortionWaveStyle) {
        let launch = style.anticipation
        let swell = style.travel * 0.4
        PaeoniaHapticPattern.play(
            [
                .buzz(at: 0, duration: launch, sharpness: 0.15),
                .tap(at: launch, sharpness: 0.7),
                .buzz(at: launch, duration: swell, sharpness: 0.3),
            ],
            curves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        .init(relativeTime: 0, value: 0.15),
                        .init(relativeTime: launch, value: 0.8),
                        .init(relativeTime: launch + 0.02, value: 0.55),
                        .init(relativeTime: launch + swell, value: 0),
                    ],
                    relativeTime: 0
                ),
            ]
        )
    }
}
