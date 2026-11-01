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
    private let showsShareButton: Bool
    /// The "Not sent yet" pill above the canvas.
    private let showsSendStatus: Bool
    private let emptyCanvasHint: LocalizedStringResource?
    @State private var isHistoryPresented = false
    @State private var isCompositionPresented = false
    @State private var isDescriptionPresented = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(ReactionStore.self) private var reactionStore: ReactionStore?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityPresentation(.media) private var showsMedia

    init(
        ownerUserID: UUID? = nil,
        coupleID: UUID? = nil,
        authorName: String? = nil,
        viewModel: WidgetDrawingViewModel? = nil,
        historyViewModel: WidgetDrawingHistoryViewModel? = nil,
        historyThumbnailLoader: (any WidgetRevisionThumbnailLoading)? = nil,
        title: LocalizedStringResource = .widgetDrawingTitle,
        showsHistory: Bool = true,
        showsShareButton: Bool = true,
        showsSendStatus: Bool = true,
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
        self.showsShareButton = showsShareButton
        self.showsSendStatus = showsSendStatus
        self.emptyCanvasHint = emptyCanvasHint
        partnerName = WidgetSyncIdentityStore.shared.load().partnerDisplayName?.trimmedNonEmpty
            ?? String(localized: .pairingCelebrationPartnerName)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { canvasContent }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                canvasContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
        .padding(.bottom, PaeoniaSpacing.space16)
        // A canvas wider than this makes strokes look thin once they shrink onto the widget.
        .paeoniaReadableWidth()
        .background(.paeoniaBackgroundSecondary)
        .paeoniaFittingNavigationTitle(Text(title))
        .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        // Description entry happens in a sheet. Its keyboard must not resize
        // this canvas and rescale the drawing underneath the composer.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar { toolbarButtons }
        .paeoniaShareToolbar(showsShareButton ? viewModel.shareable : nil, identifier: "widgetDrawing.share")
        .drawingCompositionSheet(
            isPresented: $isCompositionPresented,
            drawing: viewModel.drawing, side: viewModel.currentCanvasSide(), isLocked: false,
            description: Binding(
                get: { viewModel.accessibilityText }, set: { viewModel.updateAccessibilityText($0) }
            )
        ) { viewModel.applyEdit($0) }
        .sheet(isPresented: $isDescriptionPresented) {
            WidgetDrawingDescriptionSheet(text: Binding(
                get: { viewModel.accessibilityText }, set: { viewModel.updateAccessibilityText($0) }
            ))
        }
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
    }

    private var canvasContent: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            WidgetDrawingCanvasHeader(viewModel: viewModel, partnerName: partnerName, showsSendStatus: showsSendStatus)

            if dynamicTypeSize.isAccessibilitySize { compositionButton }

            drawingCanvas
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 280 : nil)

            if dynamicTypeSize.isAccessibilitySize {
                WidgetDrawingSetAsideBar(viewModel: viewModel)
            }

            VStack(spacing: PaeoniaSpacing.space8) {
                WidgetDrawingToolControlsView(viewModel: viewModel)
                WidgetDrawingColorControlsView(viewModel: viewModel)
                WidgetDrawingSizeControlsView(viewModel: viewModel)
            }

            if !dynamicTypeSize.isAccessibilitySize { compositionButton }
            if showsMedia || viewModel.accessibilityText.unicodeScalars.count > 500 {
                Text(viewModel.accessibilityText.trimmedNonEmpty ?? String(localized: .drawingGeometryMissing))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("widgetDrawing.description")
                Button(.mediaAccessibilityDrawingDescription) { isDescriptionPresented = true }
                    .tint(.paeoniaAccentPrimary)
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    .accessibilityIdentifier("widgetDrawing.description.edit")
            }

            bottomActions
        }
    }

    private var compositionButton: some View {
        DrawingCompositionButton { isCompositionPresented = true }
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
            // Keyboard and sheet transitions can briefly offer less than zero
            // remaining height. Keep that layout pass out of PencilKit's geometry.
            let side = max(0, min(proxy.size.width, proxy.size.height))

            canvasView
            // PencilKit coordinates, the rasterizer source rect, previews, and
            // widget rendering all use this exact square. Constraining the UIKit
            // view itself avoids recording a wider coordinate space on devices
            // where the remaining vertical space is shorter than screen width.
            .frame(width: side, height: side)
            .overlay { liveOverlay }
            .overlay { emptyCanvasHintView }
            .overlay { WidgetDrawingSizePreview(viewModel: viewModel) }
            .overlay(alignment: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize { WidgetDrawingSetAsideBar(viewModel: viewModel) }
            }
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .stroke(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault)
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
        .accessibilityIdentifier("widgetDrawing.canvas")
    }

    // MARK: - Actions

    private var bottomActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
        return layout {
            Button {
                // No confirmation: undo takes a clear back.
                viewModel.clearCanvas()
                PaeoniaHaptics.destructiveActionConfirmed()
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
            .accessibilityIdentifier("widgetDrawing.send")
            // The label crossfades between states instead of swapping in one frame.
            .animation(PaeoniaMotion.stateChange, value: viewModel.delivery)
            .animation(PaeoniaMotion.stateChange, value: viewModel.canSave)
        }
    }
}

private extension WidgetDrawingView {
    @ViewBuilder
    var sendButtonLabel: some View {
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
                Text(.widgetDrawingSaveButton)
            case .idle:
                Text(.widgetDrawingSaveButton)
            }
        }
    }

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
            tool: viewModel.canvasTool,
            onCanvasReady: viewModel.bindCanvasView,
            onDrawingChange: viewModel.updateDrawing,
            onStrokeInProgressChange: viewModel.setDrawingStrokeInProgress,
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canRevertToSavedDrawing)
            .accessibilityLabel(Text(.widgetDrawingRevertButton))
        }
        if showsHistory {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isHistoryPresented = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
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
