import PencilKit
import SwiftUI

/// The finished drawing on the result screens. While the drawing is not on the
/// phone yet, the square shows a spinner, or the failed download with Try again.
/// The drawing then fades in. The square keeps its size the whole time.
struct DrawAndGuessRevealDrawing: View {
    let viewModel: DrawAndGuessViewModel
    let side: CGFloat

    var body: some View {
        let drawing = viewModel.finalDrawing
        ZStack {
            if let drawing {
                DrawAndGuessFinalDrawingView(drawing: drawing, side: side)
                    .transition(.opacity)
            } else {
                DrawAndGuessDrawingPlaceholder(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        // Only opacity changes, so this also suits Reduce Motion.
        .animation(PaeoniaMotion.meaningfulMoment, value: drawing == nil)
    }
}

extension View {
    /// The drawing in the square is one VoiceOver element. While it is not on the
    /// phone, the spinner, or the error and its button, are reachable instead. The
    /// modifiers are the same either way, so SwiftUI keeps the square and the
    /// drawing can fade in.
    func drawAndGuessDrawingAccessibility(label: Text, hint: Text? = nil, isDrawingShown: Bool) -> some View {
        let none = Text(verbatim: "")
        return accessibilityElement(children: isDrawingShown ? .ignore : .contain)
            .accessibilityLabel(isDrawingShown ? label : none)
            .accessibilityHint(isDrawingShown ? hint ?? none : none)
    }
}

/// What the square shows while the partner's drawing is not on the phone: a
/// spinner while it downloads, or the failed download and its Try again button.
struct DrawAndGuessDrawingPlaceholder: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        GameDrawingPlaceholder(loadFailed: viewModel.drawingLoadFailed) {
            viewModel.retryLoadingDrawing()
        }
    }
}

/// The canonical drawing scaled to the square it is shown in.
struct DrawAndGuessFinalDrawingView: View {
    let drawing: DrawAndGuessFinalDrawing?
    let side: CGFloat

    var body: some View {
        GameStaticDrawing(drawing: drawing?.fitted(toSide: side) ?? PKDrawing())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
