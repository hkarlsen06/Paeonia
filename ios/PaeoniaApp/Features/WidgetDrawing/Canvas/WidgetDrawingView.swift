import PencilKit
import SwiftUI

/// Draw on the shared widget. The canvas sits on top; the tools, colors, size,
/// and the Send button sit below it, within reach of the thumb. Status lives in
/// fixed-height rows, so the canvas never changes size when the status does
/// (a resize would rescale the drawing).
struct WidgetDrawingView: View {
    @State private var viewModel: WidgetDrawingViewModel
    private let historyViewModel: WidgetDrawingHistoryViewModel?
    private let historyThumbnailLoader: (any WidgetRevisionThumbnailLoading)?
    private let partnerName: String
    private let title: LocalizedStringResource
    private let showsHistory: Bool
    private let emptyCanvasHint: LocalizedStringResource?
    @State private var isClearConfirmationPresented = false
    @State private var isHistoryPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(ReactionStore.self) private var reactionStore: ReactionStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        ownerUserID: UUID? = nil,
        coupleID: UUID? = nil,
        authorName: String? = nil,
        viewModel: WidgetDrawingViewModel? = nil,
        historyViewModel: WidgetDrawingHistoryViewModel? = nil,
        historyThumbnailLoader: (any WidgetRevisionThumbnailLoading)? = nil,
        title: LocalizedStringResource = .widgetDrawingTitle,
        showsHistory: Bool = true,
        emptyCanvasHint: LocalizedStringResource? = nil
    ) {
        _viewModel = State(
            initialValue: viewModel ?? WidgetDrawingViewModel(
                ownerUserID: ownerUserID,
                coupleID: coupleID,
                authorName: authorName,
                live: coupleID.map { WidgetLiveDrawing(coupleID: $0) }
            )
        )
        self.historyViewModel = historyViewModel
        self.historyThumbnailLoader = historyThumbnailLoader
        self.title = title
        self.showsHistory = showsHistory
        self.emptyCanvasHint = emptyCanvasHint
        partnerName = WidgetSyncIdentityStore.shared.load().partnerDisplayName?.trimmedNonEmpty
            ?? String(localized: .pairingCelebrationPartnerName)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            WidgetDrawingCanvasHeader(viewModel: viewModel, partnerName: partnerName)

            drawingCanvas

            VStack(spacing: PaeoniaSpacing.space8) {
                WidgetDrawingToolControlsView(viewModel: viewModel)
                WidgetDrawingColorControlsView(viewModel: viewModel)
                WidgetDrawingSizeControlsView(viewModel: viewModel)
            }

            bottomActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
        .padding(.bottom, PaeoniaSpacing.space16)
        // A canvas wider than this makes strokes look thin once they shrink onto the widget.
        .paeoniaReadableWidth()
        .background(.paeoniaBackgroundSecondary)
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar { toolbarButtons }
        .sheet(isPresented: $isHistoryPresented) {
            if let historyViewModel, let historyThumbnailLoader {
                WidgetDrawingHistoryView(
                    viewModel: historyViewModel,
                    thumbnailLoader: historyThumbnailLoader
                )
                .analyticsScreen("drawing_history")
            } else {
                WidgetDrawingHistoryView()
                    .analyticsScreen("drawing_history")
            }
        }
        .task {
            // The person is now looking at the drawing, so drop any lingering
            // "partner updated the widget" alerts from Notification Center.
            await DeliveredNotifications.clear(types: ["widget_updated"])
        }
        // A partner's drawing synced in while this screen was open. With unsent
        // changes on the canvas, the header says so instead of replacing them.
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetCanvasDidUpdate)) { _ in
            Task {
                await viewModel.reloadSavedDrawingFromSyncIfSafe()
                await DeliveredNotifications.clear(types: ["widget_updated"])
            }
        }
        // A drawing that was waiting for the network went out in the background.
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetUploadDidFinish)) { _ in
            Task { await viewModel.refreshDelivery() }
        }
        // Catch a sync that landed while we were backgrounded.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.startLive()
                Task {
                    await viewModel.reloadSavedDrawingFromSyncIfSafe()
                    await viewModel.refreshDelivery()
                }
            case .background:
                viewModel.stopLive()
                viewModel.persistDraftIfNeeded()
            default:
                // Control Center or the app switcher. Stay connected, so the
                // partner's changes keep arriving.
                viewModel.persistDraftIfNeeded()
            }
        }
        .onDisappear {
            viewModel.stopLive()
            viewModel.persistDraftIfNeeded()
        }
        .modifier(WidgetDrawingPencilDoubleTap(viewModel: viewModel))
        .onChange(of: viewModel.delivery) { _, delivery in
            switch delivery {
            case .sent:
                PaeoniaHaptics.drawingSaved()
            case .waiting:
                PaeoniaHaptics.drawingSent()
            case .idle, .sending:
                break
            }
        }
        .onChange(of: viewModel.partnerSentWhileEditing) { _, didSend in
            if didSend {
                PaeoniaHaptics.partnerDrawingReceived()
            }
        }
        .onChange(of: viewModel.saveFailure) { _, failure in
            guard let failure else {
                return
            }
            showBanner(for: failure)
        }
        .alert(
            Text(.widgetDrawingClearConfirmTitle),
            isPresented: $isClearConfirmationPresented
        ) {
            Button(role: .destructive) {
                viewModel.clearCanvas()
                PaeoniaHaptics.destructiveActionConfirmed()
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

    private func showBanner(for failure: WidgetDrawingSaveFailure) {
        switch failure.reason {
        case .couldNotSave:
            bannerCenter.show(
                .error(
                    title: String(localized: .widgetDrawingSaveErrorTitle),
                    message: String(localized: .widgetDrawingSaveErrorMessage)
                )
            )
        case .tooBig:
            bannerCenter.show(
                .error(
                    title: String(localized: .widgetDrawingTooBigTitle),
                    message: String(localized: .widgetDrawingTooBigMessage)
                )
            )
        }
    }

    // MARK: - Canvas

    private var drawingCanvas: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            canvasView
            // PencilKit coordinates, the rasterizer source rect, previews, and
            // widget rendering all use this exact square. Constraining the UIKit
            // view itself avoids recording a wider coordinate space on devices
            // where the remaining vertical space is shorter than screen width.
            .frame(width: side, height: side)
            .overlay { liveOverlay }
            .overlay { emptyCanvasHintView }
            .overlay { WidgetDrawingSizePreview(viewModel: viewModel) }
            .overlay(alignment: .bottom) { WidgetDrawingSetAsideBar(viewModel: viewModel) }
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            // The side is known before the saved drawing loads, so a drawing
            // from a phone with another screen size is scaled on the first try.
            .task {
                viewModel.canvasDidLayout(side: side)
                await viewModel.loadSavedDrawingIfNeeded()
                viewModel.startLive()
            }
            .onChange(of: side) { _, newSide in
                viewModel.canvasDidLayout(side: newSide)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text(.widgetDrawingCanvasLabel))
    }

    // MARK: - Actions

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
                sendButtonLabel
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!viewModel.canSave)
            // The label crossfades between states instead of swapping in one frame.
            .animation(PaeoniaMotion.stateChange, value: viewModel.delivery)
            .animation(PaeoniaMotion.stateChange, value: viewModel.canSave)
        }
    }

    @ViewBuilder
    private var sendButtonLabel: some View {
        // Unsent changes always offer Send, even while an older send is still
        // uploading; the newer drawing replaces it.
        if viewModel.canSave {
            Text(.widgetDrawingSaveButton)
        } else {
            switch viewModel.delivery {
            case .sending:
                HStack(spacing: PaeoniaSpacing.space8) {
                    ProgressView()
                        .tint(.paeoniaTextInverse)
                    Text(.widgetDrawingSaving)
                }
            case .sent:
                Label {
                    Text(.widgetDrawingSaved)
                } icon: {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            case .waiting:
                Label {
                    Text(.widgetDrawingWaitingButton)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.8)
                } icon: {
                    Image(systemName: "wifi.slash")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(Text(.widgetDrawingWaitingMessage(partnerName)))
            case .idle:
                Text(.widgetDrawingSaveButton)
            }
        }
    }
}

private extension WidgetDrawingView {
    /// The reaction target of the partner's drawing, when it is the one on screen.
    var partnersDrawingReaction: WidgetDrawingReactionTarget? {
        guard viewModel.isShowingSavedAttribution,
              let reaction = LatestWidgetDrawing.shared.reactionTarget(
                  showing: WidgetCanvasSyncService.lastSyncedRevisionID(),
                  currentUserID: reactionStore?.participants.currentUserID
              ),
              reaction.isFromPartner
        else {
            return nil
        }
        return reaction
    }

    var canvasView: PencilKitCanvasView {
        PencilKitCanvasView(
            drawing: viewModel.drawing,
            drawingRevision: viewModel.drawingRevision,
            tool: viewModel.pencilKitTool,
            toolConfigurationRevision: viewModel.toolConfigurationRevision,
            onCanvasReady: viewModel.bindCanvasView,
            onDrawingChange: viewModel.updateDrawing,
            onStrokeInProgressChange: viewModel.setDrawingStrokeInProgress,
            isFillToolSelected: viewModel.selectedTool.isFill,
            onFill: viewModel.fill,
            onDrawingApplied: viewModel.canvasDidApplyDrawing,
            onFinishRendering: viewModel.refreshDrawingFromCanvas
        )
    }

    @ToolbarContentBuilder
    var toolbarButtons: some ToolbarContent {
        // Only the partner's drawing takes a reaction. A button without one would show as an empty pill.
        if reactionStore != nil, let reaction = partnersDrawingReaction {
            ToolbarItem(placement: .topBarTrailing) {
                ReactionPickerButton(target: reaction.target, style: .toolbar)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.revertToSavedDrawing()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(!viewModel.canRevertToSavedDrawing)
            .accessibilityLabel(Text(.widgetDrawingRevertButton))
        }
        if showsHistory {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isHistoryPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel(Text(.widgetHistoryOpenButton))
            }
        }
    }

    /// A line on the empty canvas that says who the drawing is for. It fades out
    /// with the first stroke.
    @ViewBuilder
    var emptyCanvasHintView: some View {
        if let emptyCanvasHint {
            Text(emptyCanvasHint)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextTertiary)
                .multilineTextAlignment(.center)
                .padding(PaeoniaSpacing.space32)
                .opacity(viewModel.drawing.strokes.isEmpty ? 1 : 0)
                .animation(PaeoniaMotion.stateChange, value: viewModel.drawing.strokes.isEmpty)
                .allowsHitTesting(false)
        }
    }

    /// The partner's strokes while they draw them.
    @ViewBuilder
    var liveOverlay: some View {
        if let live = viewModel.live {
            WidgetLiveOverlayView(live: live)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    NavigationStack {
        WidgetDrawingView()
    }
    .environment(PaeoniaBannerCenter())
}
