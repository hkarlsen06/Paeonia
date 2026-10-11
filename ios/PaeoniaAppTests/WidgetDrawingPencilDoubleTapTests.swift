import SwiftUI
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetDrawingPencilDoubleTapTests {
    @Test func switchesBetweenTheDrawingToolAndTheEraser() {
        let viewModel = WidgetDrawingViewModel()
        viewModel.selectTool(.pencil)

        viewModel.handlePencilDoubleTap(.switchEraser)
        #expect(viewModel.selectedTool == .eraser)
        viewModel.handlePencilDoubleTap(.switchEraser)
        #expect(viewModel.selectedTool == .pencil)
    }

    @Test func otherChoicesAlsoSwitchToTheEraser() {
        let viewModel = WidgetDrawingViewModel()

        viewModel.handlePencilDoubleTap(.showColorPalette)
        #expect(viewModel.selectedTool == .eraser)
        viewModel.handlePencilDoubleTap(.showColorPalette)
        #expect(viewModel.selectedTool == .pen)
    }

    @Test func lastUsedGoesBackToThePreviousTool() {
        let viewModel = WidgetDrawingViewModel()
        viewModel.selectTool(.pencil)

        viewModel.handlePencilDoubleTap(.switchPrevious)
        #expect(viewModel.selectedTool == .pen)
        viewModel.handlePencilDoubleTap(.switchPrevious)
        #expect(viewModel.selectedTool == .pencil)
    }

    @Test func offDoesNothing() {
        let viewModel = WidgetDrawingViewModel()

        viewModel.handlePencilDoubleTap(.ignore)
        #expect(viewModel.selectedTool == .pen)
    }
}
