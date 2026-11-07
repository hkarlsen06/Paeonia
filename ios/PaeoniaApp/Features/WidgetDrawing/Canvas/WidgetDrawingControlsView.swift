import PencilKit
import SwiftUI

/// What the tool, color, and size controls need from a canvas. The widget
/// canvas and the Draw & Guess canvas both provide it, so they share the
/// controls.
protocol WidgetDrawingToolControlling: AnyObject {
    var colorChoices: [WidgetDrawingColorChoice] { get }
    var selectedTool: WidgetDrawingTool { get }
    var selectedColorChoiceID: String? { get }
    var selectedCGColor: CGColor { get }
    var isColorSelectionEnabled: Bool { get }
    var selectedLineStyle: InkLineStyle { get }
    /// The pen and the pencil draw lines. The paint bucket and the eraser do not.
    var isLineStyleSelectionEnabled: Bool { get }
    var toolWidthFraction: CGFloat { get }
    /// The width the selected tool draws, in canvas points.
    var toolWidth: CGFloat { get }
    /// The size slider is being dragged, so the canvas shows the size.
    var isAdjustingToolWidth: Bool { get }
    var canUndoDrawing: Bool { get }
    var canRedoDrawing: Bool { get }

    func selectTool(_ tool: WidgetDrawingTool)
    func selectColorChoice(_ choice: WidgetDrawingColorChoice)
    func selectCustomColor(_ color: CGColor)
    func updateToolWidthFraction(_ fraction: CGFloat)
    func setAdjustingToolWidth(_ isAdjusting: Bool)
    func selectLineStyle(_ style: InkLineStyle)
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

    /// Extra controls wrap the swatches and enlarge the color well. Otherwise
    /// they stay on one row.
    @AccessibilityPresentation(.controls) private var showsControls

    var body: some View {
        Group {
            if showsControls {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.hitTarget), spacing: 0)], spacing: 0) {
                    swatches
                }
            } else {
                HStack(spacing: 0) { swatches }
            }
        }
        .padding(.horizontal, PaeoniaSpacing.space8)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(showsControls
            ? AnyShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            : AnyShape(Capsule(style: .continuous)))
        .opacity(viewModel.isColorSelectionEnabled ? 1 : 0.52)
    }

    @ViewBuilder
    private var swatches: some View {
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
        .scaleEffect(showsControls ? 44.0 / 28.0 : 1)
        .frame(width: showsControls ? 44 : nil, height: showsControls ? 44 : nil)
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

/// The size slider, then the line style button.
struct WidgetDrawingSizeControlsView: View {
    let viewModel: any WidgetDrawingToolControlling

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            slider
            WidgetDrawingLineStyleMenu(viewModel: viewModel)
        }
        .padding(.leading, PaeoniaSpacing.space16)
        .padding(.trailing, PaeoniaSpacing.space8)
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { viewModel.toolWidthFraction },
                set: { viewModel.updateToolWidthFraction($0) }
            ),
            in: 0...1,
            label: {
                Text(.widgetDrawingSizeSlider)
            },
            onEditingChanged: { viewModel.setAdjustingToolWidth($0) }
        )
        .frame(minHeight: 44)
        .tint(isSizeEnabled ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
        .disabled(viewModel.selectedTool.isFill)
    }

    /// The eraser has a size but no color. The paint bucket has neither.
    private var isSizeEnabled: Bool {
        viewModel.isColorSelectionEnabled && !viewModel.selectedTool.isFill
    }
}

/// While the size slider is dragged, a dot as thick as the line the tool
/// draws, on an accent bubble in the middle of the canvas. The bubble keeps the
/// dot visible over any drawing underneath.
struct WidgetDrawingSizePreview: View {
    let viewModel: any WidgetDrawingToolControlling

    var body: some View {
        ZStack {
            if viewModel.isAdjustingToolWidth {
                Circle()
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: bubbleSize, height: bubbleSize)
                    .overlay { dot }
                    .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: viewModel.isAdjustingToolWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var tool: WidgetDrawingTool {
        viewModel.selectedTool
    }

    /// Fits the tool's thickest line, so the bubble keeps one size during a drag.
    private var bubbleSize: CGFloat {
        max(56, tool.drawnWidth(tool.validWidthRange.upperBound) + PaeoniaSpacing.space32)
    }

    /// The eraser has no ink, so it shows as a ring. The dark edge sits inside
    /// the dot, so the size stays exact, and keeps ink the color of the bubble
    /// visible.
    @ViewBuilder
    private var dot: some View {
        let width = tool.drawnWidth(viewModel.toolWidth)
        if tool.isEraser {
            Circle()
                .strokeBorder(.paeoniaTextInverse, lineWidth: 1.5)
                .frame(width: width, height: width)
        } else {
            Circle()
                .fill(Color(cgColor: viewModel.selectedCGColor))
                .overlay { Circle().strokeBorder(.paeoniaTextInverse.opacity(0.6), lineWidth: 1) }
                .frame(width: width, height: width)
        }
    }
}

/// Pen, pencil, paint bucket, and eraser, then undo and redo. All buttons
/// keep a 44-point minimum tap target and share the available width.
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
                        .accessibilityHidden(true)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                        .foregroundStyle(toolForeground(for: tool))
                        .background(toolBackground(for: tool))
                        .clipShape(Capsule(style: .continuous))
                        .frame(minWidth: Self.buttonSize, maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tool.accessibilityLabel))
                .accessibilityAddTraits(viewModel.selectedTool == tool ? .isSelected : [])
            }

            toolControlSeparator

            undoRedoButtons
        }
        .padding(PaeoniaSpacing.space4)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private var undoRedoButtons: some View {
        undoRedoButton(
            systemImageName: "arrow.uturn.backward",
            accessibilityLabel: .widgetDrawingUndoButton,
            accessibilityIdentifier: "widgetDrawing.undo",
            isEnabled: viewModel.canUndoDrawing,
            action: viewModel.undoDrawing
        )

        undoRedoButton(
            systemImageName: "arrow.uturn.forward",
            accessibilityLabel: .widgetDrawingRedoButton,
            accessibilityIdentifier: "widgetDrawing.redo",
            isEnabled: viewModel.canRedoDrawing,
            action: viewModel.redoDrawing
        )
    }

    private var toolControlSeparator: some View {
        Rectangle()
            .fill(.paeoniaBorder)
            .frame(width: PaeoniaRadius.strokeDefault, height: 28)
            .padding(.horizontal, PaeoniaSpacing.space4)
            .accessibilityHidden(true)
    }

    private func undoRedoButton(
        systemImageName: String,
        accessibilityLabel: LocalizedStringResource,
        accessibilityIdentifier: String,
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
                .frame(minWidth: Self.buttonSize, maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func toolForeground(for tool: WidgetDrawingTool) -> Color {
        viewModel.selectedTool == tool ? .paeoniaTextInverse : .paeoniaTextSecondary
    }

    private func toolBackground(for tool: WidgetDrawingTool) -> Color {
        viewModel.selectedTool == tool ? .paeoniaAccentPrimary : .clear
    }
}
