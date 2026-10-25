import SwiftUI

/// The 44 point button at the end of the size row. It opens a menu of line
/// styles, and its icon draws the current one.
struct WidgetDrawingLineStyleMenu: View {
    let viewModel: any WidgetDrawingToolControlling

    private static let buttonSize: CGFloat = 44

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { viewModel.selectedLineStyle },
                set: { style in
                    guard style != viewModel.selectedLineStyle else { return }
                    viewModel.selectLineStyle(style)
                    PaeoniaHaptics.selection()
                }
            )) {
                ForEach(InkLineStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                EmptyView()
            }
        } label: {
            InkLineStyleIcon(style: viewModel.selectedLineStyle)
                .foregroundStyle(isEnabled ? .paeoniaTextPrimary : .paeoniaTextTertiary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(.paeoniaSurfaceSecondary)
                .clipShape(Circle())
        }
        // Solid, dashed, dotted from the top, even when the menu opens upward.
        .menuOrder(.fixed)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(.widgetDrawingLineStyleButton))
        .accessibilityValue(Text(viewModel.selectedLineStyle.title))
        .accessibilityIdentifier("widgetDrawing.lineStyle")
    }

    private var isEnabled: Bool {
        viewModel.isLineStyleSelectionEnabled
    }
}

/// A short line drawn in `style`.
private struct InkLineStyleIcon: View {
    let style: InkLineStyle

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 1.5, y: 1.5))
            path.addLine(to: CGPoint(x: 20.5, y: 1.5))
        }
        .stroke(style: strokeStyle)
        .frame(width: 22, height: 3)
        .accessibilityHidden(true)
    }

    private var strokeStyle: StrokeStyle {
        switch style {
        case .solid:
            StrokeStyle(lineWidth: 3, lineCap: .round)
        case .dashed:
            StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 5])
        case .dotted:
            StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0, 5])
        }
    }
}
