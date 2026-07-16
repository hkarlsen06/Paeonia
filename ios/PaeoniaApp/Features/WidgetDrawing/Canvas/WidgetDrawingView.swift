import SwiftUI

struct WidgetDrawingView: View {
    @State private var viewModel: WidgetDrawingViewModel
    private let historyViewModel: WidgetDrawingHistoryViewModel?
    private let historyThumbnailLoader: (any WidgetRevisionThumbnailLoading)?
    @State private var isClearConfirmationPresented = false
    @State private var isHistoryPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase

    init(
        authorName: String? = nil,
        viewModel: WidgetDrawingViewModel? = nil,
        historyViewModel: WidgetDrawingHistoryViewModel? = nil,
        historyThumbnailLoader: (any WidgetRevisionThumbnailLoading)? = nil
    ) {
        _viewModel = State(
            initialValue: viewModel ?? WidgetDrawingViewModel(authorName: authorName)
        )
        self.historyViewModel = historyViewModel
        self.historyThumbnailLoader = historyThumbnailLoader
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            WidgetDrawingToolControlsView(viewModel: viewModel)

            WidgetDrawingSizeControlsView(viewModel: viewModel)

            WidgetDrawingColorControlsView(viewModel: viewModel)

            canvasAttribution

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
            if let historyViewModel, let historyThumbnailLoader {
                WidgetDrawingHistoryView(
                    viewModel: historyViewModel,
                    thumbnailLoader: historyThumbnailLoader
                )
            } else {
                WidgetDrawingHistoryView()
            }
        }
        .task {
            await viewModel.loadSavedDrawingIfNeeded()
            // The user is now looking at the drawing, so drop any lingering
            // "partner updated the widget" alerts from Notification Center.
            await WidgetUpdateNotifications.clearDelivered()
        }
        // A partner's update synced in while this screen was open.
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetCanvasDidUpdate)) { _ in
            Task {
                await viewModel.reloadSavedDrawingFromSyncIfSafe()
                await WidgetUpdateNotifications.clearDelivered()
            }
        }
        // Catch a sync that landed while we were backgrounded.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.reloadSavedDrawingFromSyncIfSafe() }
            }
        }
        .onChange(of: viewModel.recentlySaved) { _, recentlySaved in
            if recentlySaved {
                PaeoniaHaptics.drawingSaved()
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
            // The label crossfades through save → saving → saved instead of
            // swapping in one frame while the concurrent save settles.
            .animation(PaeoniaMotion.stateChange, value: viewModel.isSaving)
            .animation(PaeoniaMotion.stateChange, value: viewModel.recentlySaved)
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

    // Attribution for the saved drawing, sitting above the canvas: who drew it
    // (leading) and when (trailing), in the widget's own type styles. The row
    // always participates in layout, including while the first saved drawing is
    // loading and before a first-ever save, so its visibility never resizes the
    // square canvas. It is struck out while the editable canvas differs from the
    // drawing that is still displayed on the widget.
    private var canvasAttribution: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Text(verbatim: viewModel.savedDrawingAuthorName ?? " ")
                .font(PaeoniaTypography.widgetPrimary)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)

            Spacer(minLength: PaeoniaSpacing.space8)

            Text(
                verbatim: viewModel.savedDrawingCreatedAt.map(Self.attributionTimestamp) ?? " "
            )
            .font(PaeoniaTypography.widgetSecondary)
            .foregroundStyle(.paeoniaTextSecondary)
            .lineLimit(1)
        }
        .opacity(viewModel.isShowingSavedAttribution ? 1 : 0)
        .accessibilityHidden(!viewModel.isShowingSavedAttribution)
        .strikethrough(viewModel.hasUnsavedEdits)
        // Inset so the text tucks inside the canvas's rounded corners rather
        // than sitting flush at the screen edges.
        .padding(.horizontal, PaeoniaSpacing.space16)
        // Pull the row down toward the canvas, tightening the VStack's
        // default 16pt gap so the attribution reads as belonging to it.
        .padding(.bottom, -PaeoniaSpacing.space8)
    }

    /// Matches the widget's timestamp treatment: just the time today, otherwise
    /// the date.
    nonisolated private static func attributionTimestamp(_ date: Date) -> String {
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
