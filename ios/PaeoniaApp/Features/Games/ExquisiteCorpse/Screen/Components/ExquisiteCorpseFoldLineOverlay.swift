import SwiftUI

/// The dashed line at 88% of a canvas, with a small label under it that tells the
/// drawer what the partner will and won't see. Draw it over the canvas. It takes
/// no touches. The legs have no fold, so they don't get this overlay.
struct ExquisiteCorpseFoldLineOverlay: View {
    /// The canvas side.
    let side: CGFloat
    /// "[Name] only sees below this line".
    let label: LocalizedStringResource

    private var foldY: CGFloat {
        ExquisiteCorpseFold.foldY(side: side)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ExquisiteCorpseHorizontalLine()
                .stroke(.paeoniaTextTertiary, style: StrokeStyle(lineWidth: PaeoniaRadius.strokeEmphasis, dash: [6, 4]))
                .frame(width: side, height: PaeoniaRadius.strokeEmphasis)
                .offset(y: foldY - PaeoniaRadius.strokeEmphasis / 2)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.paeoniaTextTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, PaeoniaSpacing.space8)
                .frame(width: side, height: side - foldY - PaeoniaSpacing.space4, alignment: .topTrailing)
                .offset(y: foldY + PaeoniaSpacing.space4)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        // It sits on a picture, so it stays small enough for two lines to fit
        // the strip under the line, which is 12% of the canvas.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview {
    GameSquare(side: 300) {
        GameStaticDrawing(drawing: GameCanvas.fitted(ExquisiteCorpsePreviewDrawings.head, toSide: 300))
            .overlay {
                ExquisiteCorpseFoldLineOverlay(side: 300, label: .exquisiteCorpseDrawFoldLabel("Robin"))
            }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
