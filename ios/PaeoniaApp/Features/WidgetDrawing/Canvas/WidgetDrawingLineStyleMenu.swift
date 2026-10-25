import SwiftUI

/// The 44 point button at the end of the size row. It opens a popover that
/// draws each line style, and its icon draws the current one.
struct WidgetDrawingLineStyleMenu: View {
    let viewModel: any WidgetDrawingToolControlling

    @State private var isPickerOpen = false

    private static let buttonSize: CGFloat = 44

    var body: some View {
        Button {
            isPickerOpen = true
        } label: {
            InkLineStyleLine(style: viewModel.selectedLineStyle, length: 22, lineWidth: 3)
                .foregroundStyle(isEnabled ? .paeoniaTextPrimary : .paeoniaTextTertiary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(.paeoniaSurfaceSecondary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(.widgetDrawingLineStyleButton))
        .accessibilityValue(Text(viewModel.selectedLineStyle.title))
        .accessibilityIdentifier("widgetDrawing.lineStyle")
        .popover(isPresented: $isPickerOpen) {
            picker
                .presentationCompactAdaptation(.popover)
        }
    }

    private var picker: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            ForEach(InkLineStyle.allCases) { style in
                Button {
                    isPickerOpen = false
                    guard style != viewModel.selectedLineStyle else { return }
                    viewModel.selectLineStyle(style)
                    PaeoniaHaptics.selection()
                } label: {
                    InkLineStyleLine(style: style, length: 64, lineWidth: 4)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .frame(width: 96, height: Self.buttonSize)
                        .background {
                            if style == viewModel.selectedLineStyle {
                                Capsule(style: .continuous).fill(.paeoniaSurfaceSecondary)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style.title))
                .accessibilityAddTraits(style == viewModel.selectedLineStyle ? .isSelected : [])
            }
        }
        .padding(PaeoniaSpacing.space8)
    }

    private var isEnabled: Bool {
        viewModel.isLineStyleSelectionEnabled
    }
}

/// A straight line `length` points long, drawn in `style` with the same dash
/// layout the canvas uses.
private struct InkLineStyleLine: View {
    let style: InkLineStyle
    let length: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: lineWidth / 2, y: lineWidth / 2))
            path.addLine(to: CGPoint(x: length - lineWidth / 2, y: lineWidth / 2))
        }
        .stroke(style: strokeStyle)
        .frame(width: length, height: lineWidth)
        .accessibilityHidden(true)
    }

    private var strokeStyle: StrokeStyle {
        guard let pattern = style.pattern(lineWidth: lineWidth) else {
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        }
        return StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            dash: [pattern.on, pattern.period - pattern.on]
        )
    }
}
