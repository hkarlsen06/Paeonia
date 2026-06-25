import SwiftUI

/// Color, size, tool, and undo/redo controls for the widget drawing canvas.
/// Split out of `WidgetDrawingView` so the screen keeps a clear split between
/// the canvas surface, the drawing tools, and the bottom action cluster.
struct WidgetDrawingControlsView: View {
    let viewModel: WidgetDrawingViewModel

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            WidgetDrawingToolControlsView(viewModel: viewModel)
            WidgetDrawingSizeControlsView(viewModel: viewModel)
            WidgetDrawingColorControlsView(viewModel: viewModel)
        }
    }
}

struct WidgetDrawingColorControlsView: View {
    let viewModel: WidgetDrawingViewModel

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(viewModel.colorChoices) { choice in
                Button {
                    viewModel.selectColorChoice(choice)
                } label: {
                    colorSwatch(choice)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isColorSelectionEnabled)
                .accessibilityLabel(Text(choice.accessibilityLabel))
                .accessibilityAddTraits(
                    viewModel.selectedColorChoiceID == choice.id ? .isSelected : []
                )
            }

            customColorPicker
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Capsule(style: .continuous))
        .opacity(viewModel.isColorSelectionEnabled ? 1 : 0.52)
    }

    // The system color well is the custom-color control; show it bare while
    // preserving its accessibility label.
    private var customColorPicker: some View {
        ColorPicker(
            String(localized: .widgetDrawingColorCustom),
            selection: Binding(
                get: { viewModel.selectedCGColor },
                set: { viewModel.selectCustomColor($0) }
            ),
            supportsOpacity: false
        )
        .labelsHidden()
        .disabled(!viewModel.isColorSelectionEnabled)
        .opacity(viewModel.isColorSelectionEnabled ? 1 : 0.34)
    }

    private func colorSwatch(_ choice: WidgetDrawingColorChoice) -> some View {
        Circle()
            .fill(choice.color)
            .frame(width: 30, height: 30)
            .overlay {
                Circle()
                    .stroke(.paeoniaTextPrimary, lineWidth: selectedStrokeWidth(for: choice))
                    .padding(-2.5)
            }
            .opacity(viewModel.isColorSelectionEnabled ? 1 : 0.34)
    }

    private func selectedStrokeWidth(for choice: WidgetDrawingColorChoice) -> CGFloat {
        viewModel.selectedColorChoiceID == choice.id ? 2 : 0
    }
}

struct WidgetDrawingSizeControlsView: View {
    let viewModel: WidgetDrawingViewModel

    var body: some View {
        Slider(
            value: Binding(
                get: { viewModel.toolWidthFraction },
                set: { viewModel.updateToolWidthFraction($0) }
            ),
            in: 0...1,
            label: {
                Text(.widgetDrawingSizeSlider)
            },
            minimumValueLabel: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityHidden(true)
            },
            maximumValueLabel: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityHidden(true)
            }
        )
        .tint(viewModel.isColorSelectionEnabled ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
        .padding(.horizontal, PaeoniaSpacing.space16)
        .frame(maxWidth: 360)
    }
}

struct WidgetDrawingToolControlsView: View {
    let viewModel: WidgetDrawingViewModel

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            ForEach(WidgetDrawingTool.allCases) { tool in
                Button {
                    viewModel.selectTool(tool)
                } label: {
                    Image(systemName: tool.systemImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(toolForeground(for: tool))
                        .background(toolBackground(for: tool))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tool.accessibilityLabel))
                .accessibilityAddTraits(viewModel.selectedTool == tool ? .isSelected : [])
            }

            toolControlSeparator

            undoRedoButton(
                systemImageName: "arrow.uturn.backward",
                accessibilityLabel: .widgetDrawingUndoButton,
                isEnabled: viewModel.canUndoDrawing,
                action: viewModel.undoDrawing
            )

            undoRedoButton(
                systemImageName: "arrow.uturn.forward",
                accessibilityLabel: .widgetDrawingRedoButton,
                isEnabled: viewModel.canRedoDrawing,
                action: viewModel.redoDrawing
            )
        }
        .padding(PaeoniaSpacing.space8)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Capsule(style: .continuous))
    }

    private var toolControlSeparator: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(width: PaeoniaRadius.strokeDefault, height: 28)
    }

    private func undoRedoButton(
        systemImageName: String,
        accessibilityLabel: LocalizedStringResource,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityHidden(true)
                .frame(width: 40, height: 40)
                .foregroundStyle(isEnabled ? .paeoniaTextPrimary : .paeoniaTextTertiary)
                .background(isEnabled ? Color.paeoniaSurfacePrimary : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func toolForeground(for tool: WidgetDrawingTool) -> Color {
        viewModel.selectedTool == tool ? .paeoniaTextInverse : .paeoniaTextSecondary
    }

    private func toolBackground(for tool: WidgetDrawingTool) -> Color {
        viewModel.selectedTool == tool ? .paeoniaAccentPrimary : .clear
    }
}
