import PencilKit
import SwiftUI

/// What the hand-off from the watching screen to the drawing screen matches on.
nonisolated enum ExquisiteCorpseHandoff: Hashable {
    /// The strip: the bottom of the watched square becomes the top of the canvas.
    case strip
}

/// The drawer's surface: the strip of the part above (body and legs), then the
/// canvas, on one rounded surface. The canvas is square-cornered inside it, so a
/// line that ends at the bottom edge of the strip continues at the top edge of the
/// canvas, also in the corners. `GameDrawingCanvas` rounds its own corners, which
/// would clip the ink where the two meet.
struct ExquisiteCorpseDrawingSurface: View {
    let board: GameDrawingBoard
    /// The canvas side. With a strip the surface is 12% taller.
    let side: CGFloat
    let part: ExquisiteCorpsePartKind
    let partnerName: String
    /// The strip of the part above. Nil while it is not on the phone yet.
    let strip: PKDrawing?
    let stripLoadFailed: Bool
    let onRetryStrip: () -> Void
    /// Matches the strip to the watched square on the way in. Nil with Reduce Motion.
    let handoff: Namespace.ID?
    let onCanvasReady: (PKCanvasView) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if part.hasStripAbove {
                stripView
            }
            canvas
        }
        .frame(width: side)
        .background(.paeoniaBackgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var stripView: some View {
        let view = ExquisiteCorpseStripView(
            drawing: strip,
            width: side,
            accessibilityLabel: .exquisiteCorpseDrawStripA11Y(partnerName)
        )
        .overlay {
            // The whole strip is the button. The strip is shorter than a
            // button's minimum height, so a capsule would spill onto the canvas.
            if stripLoadFailed, strip == nil {
                Button(action: onRetryStrip) {
                    Label {
                        Text(.commonTryAgain)
                    } icon: {
                        Image(systemName: "wifi.slash")
                            .accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("corpse.strip.retry")
            }
        }
        if let handoff {
            view.matchedGeometryEffect(id: ExquisiteCorpseHandoff.strip, in: handoff)
        } else {
            view
        }
    }

    private var canvas: some View {
        PencilKitCanvasView(
            drawing: board.drawing,
            drawingRevision: board.drawingRevision,
            tool: board.pencilKitTool,
            toolConfigurationRevision: board.toolConfigurationRevision,
            onCanvasReady: onCanvasReady,
            onDrawingChange: board.updateDrawing,
            onStrokeInProgressChange: board.setStrokeInProgress,
            isFillToolSelected: board.selectedTool.isFill,
            onFill: board.fill,
            onDrawingApplied: board.canvasDidApplyDrawing,
            onFinishRendering: board.canvasDidFinishRendering
        )
        .task { board.canvasDidLayout(side: side) }
        .onChange(of: side) { _, newSide in board.canvasDidLayout(side: newSide) }
        .frame(width: side, height: side)
        .overlay {
            if part.showsFoldLine {
                ExquisiteCorpseFoldLineOverlay(side: side, label: .exquisiteCorpseDrawFoldLabel(partnerName))
            }
        }
        .accessibilityLabel(Text(.widgetDrawingCanvasLabel))
        .accessibilityIdentifier("corpse.canvas")
    }
}
