#if WIDGET_EXTENSION
import SwiftUI

/// The streak ring: a dim track with a lit left half for this person and a lit
/// right half for the partner, or one closed circle when both took part. The Lock
/// Screen and Home Screen streak widgets draw it with their own colors.
struct StreakRingView: View {
    let ring: LockScreenStreak.Ring
    let lineWidth: CGFloat
    let track: AnyShapeStyle
    let lit: AnyShapeStyle

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            ForEach(Array(ring.arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(lit, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
#endif
