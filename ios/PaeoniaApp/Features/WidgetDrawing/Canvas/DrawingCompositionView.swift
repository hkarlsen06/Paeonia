import PencilKit
import SwiftUI

extension DrawingComposition.Shape {
    nonisolated var label: LocalizedStringResource {
        switch self {
        case .circle: .drawingComposeCircle
        case .rectangle: .drawingComposeRectangle
        case .triangle: .drawingComposeTriangle
        case .horizontalLine: .drawingComposeHorizontal
        case .verticalLine: .drawingComposeVertical
        case .diagonalLine: .drawingComposeDiagonal
        }
    }
}

/// A visible alternative to tracing with a finger, using native form controls
/// for speech, switch and keyboard interaction.
struct DrawingCompositionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(.drawingComposeTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
        .accessibilityIdentifier("drawing.compose")
    }
}

extension View {
    /// Attach to the feature root, outside adaptive tool rows and canvas layouts,
    /// so a drawing update or reflow cannot remove the sheet's presenter.
    func drawingCompositionSheet(
        isPresented: Binding<Bool>, drawing: PKDrawing, side: CGFloat, isLocked: Bool,
        description: Binding<String>? = nil, fixedInkColor: UIColor? = nil,
        apply: @escaping (PKDrawing) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            DrawingCompositionView(
                drawing: drawing, sourceDrawing: drawing, side: side, isLocked: isLocked,
                apply: apply, description: description, fixedInkColor: fixedInkColor
            )
        }
    }
}

private struct DrawingCompositionView: View {
    @State var drawing: PKDrawing
    let sourceDrawing: PKDrawing
    let side: CGFloat
    let isLocked: Bool
    let apply: (PKDrawing) -> Void
    var description: Binding<String>?
    var fixedInkColor: UIColor?
    @State private var shape: DrawingComposition.Shape = .circle
    @State private var x = 50.0
    @State private var y = 50.0
    @State private var size = 30.0
    @State private var colorID = WidgetDrawingColorChoice.palette[0].id
    @State private var selected: Int?
    @State private var undo: [PKDrawing] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                compositionSection
                if let description {
                    Section {
                        TextField(text: description, axis: .vertical) { Text(.drawingDescriptionTitle) }
                            .accessibilityIdentifier("drawing.description")
                        if description.wrappedValue.unicodeScalars.count > 500 {
                            Text(.drawingDescriptionTooLong)
                                .foregroundStyle(.paeoniaErrorText)
                        }
                        Text(.drawingDescriptionHint)
                    }
                }
                Section {
                    DrawingGeometryReadout(drawing: drawing, side: side)
                }
            }
            .disabled(isLocked)
            .onChange(of: sourceDrawing) { _, latest in
                // Keep this editing session's undo stack when PencilKit publishes a
                // rendered copy of our own edits or the keyboard changes the canvas layout.
                guard undo.isEmpty,
                      latest.paeoniaContentSignature != drawing.paeoniaContentSignature else { return }
                drawing = latest
                selected = nil
                undo.removeAll()
            }
            .paeoniaGroupedList()
            .keyboardDoneToolbar()
            .navigationTitle(Text(.drawingComposeTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(.commonDone) }
                        .accessibilityIdentifier("drawing.compose.done")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var compositionSection: some View {
        Section {
            Text(.drawingComposeInstructions)
            Picker(selection: $selected) {
                Text(.drawingComposeNew).tag(Optional<Int>.none)
                ForEach(drawing.strokes.indices, id: \.self) { index in
                    Text(.drawingComposeMark(Int32(index + 1))).tag(Optional(index))
                }
            } label: { Text(.drawingComposeSelection) }
            .onChange(of: selected) { _, index in loadPosition(index) }
            Picker(selection: $shape) {
                ForEach(DrawingComposition.Shape.allCases) { Text($0.label).tag($0) }
            } label: { Text(.drawingComposeShape) }
            Stepper(value: $x, in: 5...95, step: 5) { Text(.drawingComposeX(Int32(x))) }
            Stepper(value: $y, in: 5...95, step: 5) { Text(.drawingComposeY(Int32(y))) }
            Stepper(value: $size, in: 5...90, step: 5) { Text(.drawingComposeSize(Int32(size))) }
            if fixedInkColor == nil {
                Picker(selection: $colorID) {
                    ForEach(WidgetDrawingColorChoice.palette) { Text($0.accessibilityLabel).tag($0.id) }
                } label: { Text(.drawingComposeColor) }
            }
            Button { addOrReplace() } label: {
                Text(selected == nil ? .drawingComposeAdd : .drawingComposeReplace)
            }
            .accessibilityIdentifier("drawing.compose.apply")
            if selected != nil {
                Button(role: .destructive) {
                    commit(DrawingComposition.replacing(selected, in: drawing, with: nil))
                    selected = nil
                } label: { Text(.drawingComposeRemove) }
            }
            Button {
                guard !isLocked, let previous = undo.popLast() else { return }
                drawing = previous
                selected = nil
                apply(previous)
            } label: { Text(.widgetDrawingUndoButton) }
            .disabled(undo.isEmpty)
            .accessibilityIdentifier("drawing.compose.undo")
        }
    }

    private func loadPosition(_ index: Int?) {
        guard let index, drawing.strokes.indices.contains(index), side > 0 else { return }
        let stroke = drawing.strokes[index]
        if let existingShape = DrawingComposition.shape(of: stroke) { shape = existingShape }
        if let color = WidgetDrawingColorChoice.palette.first(where: { $0.uiColor.isEqual(stroke.ink.color) }) {
            colorID = color.id
        }
        let bounds = stroke.renderBounds
        x = Double(min(max(bounds.midX / side * 100, 5), 95))
        y = Double(min(max(bounds.midY / side * 100, 5), 95))
        size = Double(min(max(max(bounds.width, bounds.height) / side * 100, 5), 90))
    }

    private func addOrReplace() {
        let color = fixedInkColor ?? WidgetDrawingColorChoice.palette.first { $0.id == colorID }?.uiColor
            ?? WidgetDrawingColorChoice.palette[0].uiColor
        guard let stroke = DrawingComposition.stroke(shape: shape, x: x, y: y, size: size, side: side, color: color)
        else { return }
        commit(DrawingComposition.replacing(selected, in: drawing, with: stroke))
    }

    private func commit(_ next: PKDrawing) {
        guard !isLocked else { return }
        undo.append(drawing)
        drawing = next
        apply(next)
    }
}

struct DrawingGeometryReadout: View {
    let drawing: PKDrawing
    let side: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.drawingGeometryMissing)
            ForEach(
                Array(DrawingGeometryDescription.marks(drawing, side: side).enumerated()), id: \.offset
            ) { index, mark in
                Text(mark)
                    .accessibilityIdentifier("drawing.geometry.mark.\(index)")
            }
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
