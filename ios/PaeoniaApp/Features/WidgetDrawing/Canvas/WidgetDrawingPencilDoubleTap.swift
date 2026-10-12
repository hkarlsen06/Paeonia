import SwiftUI

/// Double-tapping Apple Pencil switches tools the way the person set it up in
/// Settings > Apple Pencil.
struct WidgetDrawingPencilDoubleTap: ViewModifier {
    let viewModel: any WidgetDrawingToolControlling
    @Environment(\.preferredPencilDoubleTapAction) private var preferredAction

    func body(content: Content) -> some View {
        content.onPencilDoubleTap { _ in
            viewModel.handlePencilDoubleTap(preferredAction)
        }
    }
}
