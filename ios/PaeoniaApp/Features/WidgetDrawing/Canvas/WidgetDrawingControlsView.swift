import PencilKit
import SwiftUI

/// What the tool, color, and size controls need from a canvas. The widget
/// canvas and the Draw & Guess canvas both provide it, so they share the
/// controls.
@MainActor
protocol WidgetDrawingToolControlling: AnyObject {
    var colorChoices: [WidgetDrawingColorChoice] { get }
    var selectedTool: WidgetDrawingTool { get }
    var selectedColorChoiceID: String? { get }
    var selectedCGColor: CGColor { get }
    var isColorSelectionEnabled: Bool { get }
    var toolWidthFraction: CGFloat { get }
    var canUndoDrawing: Bool { get }
    var canRedoDrawing: Bool { get }

    func selectTool(_ tool: WidgetDrawingTool)
    func selectColorChoice(_ choice: WidgetDrawingColorChoice)
    func selectCustomColor(_ color: CGColor)
    func updateToolWidthFraction(_ fraction: CGFloat)
    func undoDrawing()
    func redoDrawing()
    func handlePencilDoubleTap(_ action: PencilPreferredAction)
}

extension WidgetDrawingViewModel: WidgetDrawingToolControlling {}

/// Color swatches and the custom color well. Every swatch keeps a 44 point
/// tap target even though the visible dot is smaller.
struct WidgetDrawingColorControlsView: View {
    let viewModel: any WidgetDrawingToolControlling

    private static let swatchSize: CGFloat = 30
    private static let hitTarget: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.colorChoices) { choice in
                Button {
                    guard viewModel.selectedColorChoiceID != choice.id else { return }
                    viewModel.selectColorChoice(choice)
                    PaeoniaHaptics.selection()
                } label: {
                    colorSwatch(choice)
                        .frame(maxWidth: .infinity, minHeight: Self.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isColorSelectionEnabled)
                .accessibilityLabel(Text(choice.accessibilityLabel))
                .accessibilityAddTraits(
                    viewModel.selectedColorChoiceID == choice.id ? .isSelected : []
                )
            }

            customColorPicker
                .frame(maxWidth: .infinity, minHeight: Self.hitTarget)
        }
        .padding(.horizontal, PaeoniaSpacing.space8)
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
            .frame(width: Self.swatchSize, height: Self.swatchSize)
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
    let viewModel: any WidgetDrawingToolControlling

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

/// Pen, pencil, and eraser, then undo and redo. All buttons are 44 points.
struct WidgetDrawingToolControlsView: View {
    let viewModel: any WidgetDrawingToolControlling

    private static let buttonSize: CGFloat = 44

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            ForEach(WidgetDrawingTool.allCases) { tool in
                Button {
                    guard viewModel.selectedTool != tool else { return }
                    viewModel.selectTool(tool)
                    PaeoniaHaptics.selection()
                } label: {
                    Image(systemName: tool.systemImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
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
        .padding(PaeoniaSpacing.space4)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Capsule(style: .continuous))
    }

    private var toolControlSeparator: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(width: PaeoniaRadius.strokeDefault, height: 28)
            .padding(.horizontal, PaeoniaSpacing.space4)
            .accessibilityHidden(true)
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
                .frame(width: Self.buttonSize, height: Self.buttonSize)
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
