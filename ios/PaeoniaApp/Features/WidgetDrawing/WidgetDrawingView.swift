import SwiftUI

struct WidgetDrawingView: View {
    @State private var viewModel: WidgetDrawingViewModel
    @State private var isClearConfirmationPresented = false
    @State private var isHistoryPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    init(authorName: String? = nil) {
        _viewModel = State(initialValue: WidgetDrawingViewModel(authorName: authorName))
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            WidgetDrawingToolControlsView(viewModel: viewModel)

            WidgetDrawingSizeControlsView(viewModel: viewModel)

            WidgetDrawingColorControlsView(viewModel: viewModel)

            drawingCanvas

            bottomActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.space24)
        .background(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(.widgetDrawingTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isHistoryPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel(Text(.widgetHistoryOpenButton))
            }
        }
        .sheet(isPresented: $isHistoryPresented) {
            WidgetDrawingHistoryView()
        }
        .task {
            await viewModel.loadSavedDrawingIfNeeded()
        }
        .onChange(of: viewModel.recentlySaved) { _, recentlySaved in
            if recentlySaved {
                PaeoniaHaptics.drawingSent()
            }
        }
        .onChange(of: viewModel.saveFailure) { _, failure in
            guard failure != nil else {
                return
            }
            bannerCenter.show(
                .error(
                    title: String(localized: .widgetDrawingSaveErrorTitle),
                    message: String(localized: .widgetDrawingSaveErrorMessage)
                )
            )
        }
        .alert(
            Text(.widgetDrawingClearConfirmTitle),
            isPresented: $isClearConfirmationPresented
        ) {
            Button(role: .destructive) {
                viewModel.clearCanvas()
            } label: {
                Text(.widgetDrawingClearConfirmAction)
            }

            Button(role: .cancel) {} label: {
                Text(.widgetDrawingClearCancel)
            }
        } message: {
            Text(.widgetDrawingClearConfirmMessage)
        }
    }

    private var bottomActions: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Button {
                isClearConfirmationPresented = true
            } label: {
                Text(.widgetDrawingClearButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .disabled(!viewModel.canClear)

            Button {
                Task { await viewModel.save() }
            } label: {
                saveButtonLabel
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!viewModel.canSave)
            .accessibilityLabel(Text(.widgetDrawingSaveButton))
        }
    }

    @ViewBuilder
    private var saveButtonLabel: some View {
        if viewModel.isSaving {
            HStack(spacing: PaeoniaSpacing.space8) {
                ProgressView()
                    .tint(.paeoniaTextInverse)
                Text(.widgetDrawingSaving)
            }
        } else if viewModel.recentlySaved {
            Label {
                Text(.widgetDrawingSaved)
            } icon: {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        } else {
            Text(.widgetDrawingSaveButton)
        }
    }

    private var drawingCanvas: some View {
        PencilKitCanvasView(
            drawing: $viewModel.drawing,
            tool: viewModel.pencilKitTool,
            toolConfigurationRevision: viewModel.toolConfigurationRevision,
            onCanvasReady: viewModel.bindCanvasView,
            onDrawingChange: viewModel.updateDrawing
        )
        // The widget container uses the primary plum; matching it here makes the
        // canvas an exact preview of what the saved drawing shows on the Home
        // Screen. The screen behind sits one step deeper so the canvas reads as
        // a raised surface.
        .background(.paeoniaBackgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
        }
        // Fill the space left by the controls and the bottom row as the largest
        // possible square, so freeing vertical space grows the canvas.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text(.widgetDrawingCanvasLabel))
    }
}

#Preview {
    NavigationStack {
        WidgetDrawingView()
    }
    .environment(PaeoniaBannerCenter())
}
