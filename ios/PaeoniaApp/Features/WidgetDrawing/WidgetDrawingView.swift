import SwiftUI

struct WidgetDrawingView: View {
    @State private var viewModel: WidgetDrawingViewModel
    @State private var isClearConfirmationPresented = false
    @State private var isHistoryPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase

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
            // The user is now looking at the drawing, so drop any lingering
            // "partner updated the widget" alerts from Notification Center.
            await WidgetUpdateNotifications.clearDelivered()
        }
        // A partner's update synced in while this screen was open.
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetCanvasDidUpdate)) { _ in
            Task { await viewModel.reloadSavedDrawingFromSyncIfSafe() }
        }
        // Catch a sync that landed while we were backgrounded.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.reloadSavedDrawingFromSyncIfSafe() }
            }
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
        // Attribution for the saved drawing on the canvas: who drew it (top
        // leading) and when (bottom trailing), in the widget's own type styles.
        // Struck out the moment the canvas is edited, until the next save.
        .overlay(alignment: .topLeading) {
            canvasAuthorLabel
        }
        .overlay(alignment: .bottomTrailing) {
            canvasTimestampLabel
        }
        // Fill the space left by the controls and the bottom row as the largest
        // possible square, so freeing vertical space grows the canvas.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text(.widgetDrawingCanvasLabel))
    }

    @ViewBuilder
    private var canvasAuthorLabel: some View {
        if viewModel.isShowingSavedAttribution,
           let name = viewModel.savedDrawingAuthorName,
           !name.isEmpty {
            Text(verbatim: name)
                .font(PaeoniaTypography.widgetPrimary)
                .foregroundStyle(.paeoniaTextPrimary)
                .strikethrough(viewModel.hasUnsavedEdits)
                .lineLimit(1)
                .padding(PaeoniaSpacing.space16)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var canvasTimestampLabel: some View {
        if viewModel.isShowingSavedAttribution,
           let createdAt = viewModel.savedDrawingCreatedAt {
            Text(Self.attributionTimestamp(createdAt))
                .font(PaeoniaTypography.widgetSecondary)
                .foregroundStyle(.paeoniaTextSecondary)
                .strikethrough(viewModel.hasUnsavedEdits)
                .lineLimit(1)
                .padding(PaeoniaSpacing.space16)
                .allowsHitTesting(false)
        }
    }

    /// Matches the widget's timestamp treatment: just the time today, otherwise
    /// the date.
    private static func attributionTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    NavigationStack {
        WidgetDrawingView()
    }
    .environment(PaeoniaBannerCenter())
}
