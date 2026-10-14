import PencilKit
import SwiftUI

/// What a player sees while the partner draws live: the partner's square with the
/// top 88% covered by the back of the folded paper and the strip open below it.
///
/// A soft glow moves behind the paper where the partner's pen is, so the player
/// feels the drawing happen without seeing it. The strip shows the strokes that
/// reach the bottom 12%. `pulse` goes up when the partner taps Done, and the paper
/// gives one soft pulse. The legs leave no strip, so while they are drawn the paper
/// covers the whole square (`showsStrip` false). The square clips nothing, so wrap
/// it in `GameSquare` for the rounded corners and the border.
struct ExquisiteCorpseFoldedPaper: View {
    let side: CGFloat
    /// The partner's pen, from 0 to 1 across the part. Nil while it is lifted.
    let penPosition: CGPoint?
    /// The partner's strokes in the strip, at the canonical side.
    let strip: PKDrawing?
    /// Goes up by one each time the partner taps Done.
    let pulse: Int
    var showsStrip = true
    let accessibilityLabel: LocalizedStringResource

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var paperHeight: CGFloat {
        showsStrip ? ExquisiteCorpseFold.foldY(side: side) : side
    }

    var body: some View {
        // Read here, because the keyframes run later and outside the environment.
        let pulseScale: CGFloat = reduceMotion ? 1 : Self.pulseScale
        ZStack(alignment: .top) {
            if showsStrip {
                stripDrawing
            }
            // The shadow falls on the strip, so the bottom edge reads as lifted.
            ExquisiteCorpsePaperBack()
                .frame(width: side, height: paperHeight)
                .keyframeAnimator(initialValue: Pulse(), trigger: pulse) { content, value in
                    content
                        .scaleEffect(value.scale)
                        .brightness(value.brightness)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(pulseScale, duration: Self.pulseRise)
                        CubicKeyframe(1, duration: Self.pulseFall)
                    }
                    KeyframeTrack(\.brightness) {
                        CubicKeyframe(Self.pulseBrightness, duration: Self.pulseRise)
                        CubicKeyframe(0, duration: Self.pulseFall)
                    }
                }
                .shadow(color: .paeoniaBackgroundSecondary.opacity(0.9), radius: 7, y: 4)
            ExquisiteCorpsePenGlow(pen: penPosition, side: side)
        }
        .frame(width: side, height: side, alignment: .top)
        .background(.paeoniaBackgroundPrimary)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// The strip, drawn at the full square so its strokes sit where the partner
    /// drew them, and cut to the strip so nothing above the fold can show.
    private var stripDrawing: some View {
        GameStaticDrawing(drawing: GameCanvas.fitted(strip ?? PKDrawing(), toSide: side))
            .frame(width: side, height: side)
            .clipShape(Path(ExquisiteCorpseFold.stripRect(side: side)))
            .allowsHitTesting(false)
    }

    private static let pulseScale: CGFloat = 1.012
    private static let pulseBrightness = 0.12
    private static let pulseRise: TimeInterval = PaeoniaMotion.motionDefault
    private static let pulseFall: TimeInterval = PaeoniaMotion.motionSlow + 0.2

    private struct Pulse {
        var scale: CGFloat = 1
        var brightness = 0.0
    }
}

/// A soft glow where the partner's pen is. It slides between positions, fades
/// out while the pen is lifted and comes back at the new spot instead of sliding
/// in from the old one. With Reduce Motion it never slides, it only fades.
private struct ExquisiteCorpsePenGlow: View {
    /// From 0 to 1 across the part. Nil while the pen is lifted.
    let pen: CGPoint?
    let side: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var point = CGPoint(x: 0.5, y: 0.5)
    @State private var isShown = false

    var body: some View {
        Circle()
            .fill(.paeoniaAccentPrimary)
            .frame(width: Self.diameter, height: Self.diameter)
            .blur(radius: Self.blurRadius)
            .opacity(isShown ? Self.peakOpacity : 0)
            .position(x: point.x * side, y: point.y * side)
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { move(to: pen, from: nil) }
            .onChange(of: pen) { old, new in move(to: new, from: old) }
    }

    private func move(to new: CGPoint?, from old: CGPoint?) {
        guard let new else {
            // The glow stays where it was and fades.
            withAnimation(PaeoniaMotion.meaningfulMoment) { isShown = false }
            return
        }
        if old != nil, !reduceMotion {
            withAnimation(Self.travel) { point = new }
        } else {
            var jump = Transaction()
            jump.disablesAnimations = true
            withTransaction(jump) { point = new }
        }
        if !isShown {
            withAnimation(PaeoniaMotion.stateChange) { isShown = true }
        }
    }

    private static let diameter: CGFloat = 56
    private static let blurRadius: CGFloat = 16
    private static let peakOpacity = 0.55
    /// A spring, so a new position (about 8 a second) redirects the glow without
    /// stopping it first.
    private static let travel = Animation.smooth(duration: PaeoniaMotion.motionSlow)
}

#if DEBUG
private struct ExquisiteCorpseFoldedPaperPreview: View {
    @State private var pen: CGPoint? = CGPoint(x: 0.4, y: 0.4)
    @State private var pulse = 0

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            GameSquare(side: 260) {
                ExquisiteCorpseFoldedPaper(
                    side: 260,
                    penPosition: pen,
                    strip: ExquisiteCorpsePreviewDrawings.headStrip,
                    pulse: pulse,
                    accessibilityLabel: .exquisiteCorpseWaitDrawingNowHead("Robin")
                )
            }
            HStack {
                Button {
                    pen = CGPoint(x: .random(in: 0.1...0.9), y: .random(in: 0.1...0.8))
                } label: {
                    Text(verbatim: "Move pen")
                }
                Button { pen = nil } label: { Text(verbatim: "Lift pen") }
                Button { pulse += 1 } label: { Text(verbatim: "Pulse") }
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ExquisiteCorpseFoldedPaperPreview()
}
#endif
