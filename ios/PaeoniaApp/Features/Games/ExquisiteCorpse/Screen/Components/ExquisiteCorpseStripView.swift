import PencilKit
import SwiftUI

/// The bottom 12% of the part before, shown right above the canvas. It uses the
/// canvas's scale, so a line that ends at the bottom edge of the part above
/// continues at the top edge of the canvas. A dashed line along its bottom edge
/// marks where the canvas starts.
struct ExquisiteCorpseStripView: View {
    /// The strip at the canonical side. Nil while the strip is not on the phone yet.
    let drawing: PKDrawing?
    /// The canvas width. The strip is 12% as tall.
    let width: CGFloat
    let accessibilityLabel: LocalizedStringResource

    private var height: CGFloat {
        width * ExquisiteCorpseFold.stripFraction
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let drawing {
                // The whole square, so strokes sit where they were drawn. The frame
                // below cuts it down to the bottom strip.
                GameStaticDrawing(drawing: drawing, side: width)
                    .frame(width: width, height: width)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
        .clipped()
        .background(.paeoniaBackgroundPrimary)
        .overlay(alignment: .bottom) {
            ExquisiteCorpseHorizontalLine()
                .stroke(.paeoniaTextTertiary, style: StrokeStyle(lineWidth: PaeoniaRadius.strokeDefault, dash: [4, 3]))
                .frame(height: PaeoniaRadius.strokeDefault)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        ExquisiteCorpseStripView(
            drawing: ExquisiteCorpsePreviewDrawings.headStrip,
            width: 300,
            accessibilityLabel: .exquisiteCorpseDrawStripA11Y("Robin")
        )
        Rectangle()
            .fill(.paeoniaBackgroundPrimary)
            .frame(width: 300, height: 120)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
