import PencilKit
import SwiftUI

/// The drawer's canvas: the square with the PencilKit canvas bound to a board.
/// The board hears the canvas side on every layout, so a drawing made on a phone
/// of another size scales with it. `onCanvasReady` hands the game the underlying
/// canvas view, for example to attach the live room.
struct GameDrawingCanvas: View {
    let board: GameDrawingBoard
    let side: CGFloat
    let onCanvasReady: (PKCanvasView) -> Void
    var identifier = "game.canvas"

    var body: some View {
        GameSquare(side: side) {
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
            .overlay { WidgetDrawingSizePreview(viewModel: board) }
        }
        .accessibilityLabel(Text(.widgetDrawingCanvasLabel))
        .accessibilityIdentifier(identifier)
    }
}

/// The tool, color and size rows under the canvas.
struct GameDrawingTools: View {
    let board: GameDrawingBoard

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            WidgetDrawingToolControlsView(viewModel: board)
            WidgetDrawingColorControlsView(viewModel: board)
            WidgetDrawingSizeControlsView(viewModel: board)
        }
    }
}

extension View {
    /// "Clear" in the trailing toolbar. It asks first, in an alert in the middle
    /// of the screen, and clears the board only after the person confirms.
    func gameClearDrawingToolbar(board: GameDrawingBoard, identifier: String = "game.clear") -> some View {
        modifier(GameClearDrawingToolbar(board: board, identifier: identifier))
    }
}

private struct GameClearDrawingToolbar: ViewModifier {
    let board: GameDrawingBoard
    let identifier: String

    @State private var isConfirmationPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isConfirmationPresented = true
                    } label: {
                        Text(.widgetDrawingClearButton)
                    }
                    .disabled(board.isEmpty)
                    .accessibilityIdentifier(identifier)
                }
            }
            .alert(Text(.gamesDrawingClearTitle), isPresented: $isConfirmationPresented) {
                Button(role: .destructive) {
                    board.clear()
                    PaeoniaHaptics.destructiveActionConfirmed()
                } label: {
                    Text(.gamesDrawingClearAction)
                }
                Button(role: .cancel) {} label: {
                    Text(.gamesDrawingClearCancel)
                }
            } message: {
                Text(.gamesDrawingClearMessage)
            }
    }
}
