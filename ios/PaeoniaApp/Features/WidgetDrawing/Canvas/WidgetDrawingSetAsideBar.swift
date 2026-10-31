import SwiftUI

/// Sits over the canvas while a newer drawing replaced the person's unsent one.
/// It floats instead of taking a row, so the canvas never changes size.
struct WidgetDrawingSetAsideBar: View {
    let viewModel: WidgetDrawingViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDiscardConfirmationPresented = false

    var body: some View {
        if viewModel.setAsideDrawing != nil {
            HStack(spacing: PaeoniaSpacing.space4) {
                Button {
                    viewModel.restoreSetAsideDrawing()
                } label: {
                    Label {
                        Text(.widgetDrawingSetAsideRestore)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .padding(.leading, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }

                Button {
                    isDiscardConfirmationPresented = true
                } label: {
                    Image(systemName: "xmark")
                        .padding(.horizontal, PaeoniaSpacing.space12)
                        .padding(.vertical, PaeoniaSpacing.space8)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(.widgetDrawingSetAsideDiscard))
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
            .padding(PaeoniaSpacing.space8)
            .transition(.opacity)
            .alert(Text(.widgetDrawingSetAsideDiscardTitle), isPresented: $isDiscardConfirmationPresented) {
                Button(role: .destructive) {
                    viewModel.discardSetAsideDrawing()
                } label: {
                    Text(.widgetDrawingSetAsideDiscardAction)
                }
                Button(role: .cancel) {} label: {
                    Text(.widgetDrawingSetAsideKeep)
                }
            } message: {
                Text(.widgetDrawingSetAsideDiscardMessage)
            }
        }
    }
}
