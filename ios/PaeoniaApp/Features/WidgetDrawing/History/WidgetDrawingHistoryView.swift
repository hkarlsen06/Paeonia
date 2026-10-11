import SwiftUI
import UIKit

/// Builds the gateway the history timeline reads through, falling back to a
/// no-op when no Convex client is configured (previews, signed-out states).
nonisolated enum WidgetDrawingHistoryFactory {
    static func makeGateway() -> any WidgetCanvasGateway {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return NoOpWidgetCanvasGateway()
        }
        return LiveWidgetCanvasGateway(client: client)
    }
}

/// A paginated, newest-first timeline of the couple's saved drawings. Each entry
/// shows who drew it above and when it was saved below. Read-only.
struct WidgetDrawingHistoryView: View {
    @State private var viewModel: WidgetDrawingHistoryViewModel
    private let thumbnailLoader: any WidgetRevisionThumbnailLoading
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(viewModel: WidgetDrawingHistoryViewModel, thumbnailLoader: any WidgetRevisionThumbnailLoading) {
        _viewModel = State(initialValue: viewModel)
        self.thumbnailLoader = thumbnailLoader
    }

    /// Production composition: a live gateway shared by the timeline reads and
    /// the thumbnail loader, with the last-known nicknames for labeling.
    init() {
        let gateway = WidgetDrawingHistoryFactory.makeGateway()
        let loader = WidgetRevisionThumbnailLoader(gateway: gateway)
        self.init(
            viewModel: WidgetDrawingHistoryViewModel(
                gateway: gateway,
                identity: WidgetSyncIdentityStore.shared.load(),
                exporter: loader,
                photoSaver: PhotoLibrarySaver()
            ),
            thumbnailLoader: loader
        )
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.paeoniaBackgroundSecondary)
                .navigationTitle(Text(.widgetHistoryTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text(.widgetHistoryDone)
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadInitialIfNeeded()
        }
        // The live canvas feed saved a new drawing while the timeline is open.
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetCanvasDidUpdate)) { _ in
            Task { await viewModel.refreshNewest() }
        }
        .alert(
            Text(.widgetHistorySavePermissionTitle),
            isPresented: saveAlertBinding
        ) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.commonOpenSettings)
            }

            Button(role: .cancel) {} label: {
                Text(.commonCancel)
            }
        } message: {
            Text(.widgetHistorySavePermissionMessage)
        }
    }

    /// Drives the centered permission alert. Permission denial is the one save
    /// outcome the person must act on, so it gets an explicit dialog; other
    /// failures just reset the button (see the view model).
    private var saveAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.saveAlert != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissSaveAlert()
                }
            }
        )
    }

    private var content: some View {
        ZStack {
            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(.paeoniaAccentPrimary)
            case .failed:
                failedState
            case .loaded:
                if viewModel.isEmpty {
                    emptyState
                } else {
                    timeline
                }
            }
        }
        // The spinner dissolves into the timeline (or empty/error state) instead of
        // being swapped in one frame. A fade only, so Reduce Motion needs no branch.
        .animation(PaeoniaMotion.stateChange, value: viewModel.phase)
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: PaeoniaSpacing.space24) {
                ForEach(viewModel.items) { item in
                    WidgetDrawingHistoryRow(
                        item: item,
                        loader: thumbnailLoader,
                        saveState: viewModel.saveState(for: item.id),
                        onSave: { Task { await viewModel.saveToDevice(item) } }
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: item)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .tint(.paeoniaAccentPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PaeoniaSpacing.space8)
                }

                if viewModel.loadMoreFailed {
                    loadMoreFailedRow
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space20)
        }
    }

    /// Shown below the last row when an older page failed to load. The last row's
    /// own load only fires once, so this button is the way to try again.
    private var loadMoreFailedRow: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Text(.widgetHistoryLoadMoreFailed)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.retryLoadMore() }
            } label: {
                Text(.widgetHistoryRetry)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        PaeoniaEmptyStateView(
            title: .widgetHistoryEmptyTitle,
            message: .widgetHistoryEmptyMessage(viewModel.partnerName),
            systemImage: "photo.on.rectangle.angled"
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    private var failedState: some View {
        PaeoniaEmptyStateView(
            title: .widgetHistoryErrorTitle,
            message: .widgetHistoryErrorMessage,
            systemImage: "exclamationmark.triangle"
        ) {
            Button {
                Task { await viewModel.retry() }
            } label: {
                Text(.widgetHistoryRetry)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }
}

/// One drawing in the timeline, laid out like a chat bubble: the signed-in
/// person's drawings sit on the trailing edge, the partner's on the leading
/// edge, with the nickname above and the save time below on the matching side.
private struct WidgetDrawingHistoryRow: View {
    let item: WidgetDrawingHistoryItem
    let loader: any WidgetRevisionThumbnailLoading
    let saveState: WidgetDrawingHistoryViewModel.SaveButtonState
    let onSave: () -> Void

    /// Roughly half the screen, leaving the opposite side open so the author is
    /// obvious at a glance.
    private static let widthFraction: CGFloat = 0.6

    var body: some View {
        VStack(alignment: item.isMine ? .trailing : .leading, spacing: PaeoniaSpacing.space8) {
            Text(item.authorName ?? String(localized: .widgetHistoryUnknownAuthor))
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            WidgetDrawingHistoryThumbnail(
                item: item,
                loader: loader,
                saveState: saveState,
                onSave: onSave
            )
            .containerRelativeFrame(.horizontal) { width, _ in width * Self.widthFraction }

            Text(item.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: item.isMine ? .trailing : .leading)
    }
}

/// Lazily loads and renders a revision's thumbnail over the same plum container
/// the widget uses, so the timeline reads like a stack of Home Screen widgets.
private struct WidgetDrawingHistoryThumbnail: View {
    let item: WidgetDrawingHistoryItem
    let loader: any WidgetRevisionThumbnailLoading
    let saveState: WidgetDrawingHistoryViewModel.SaveButtonState
    let onSave: () -> Void
    @State private var loadState: LoadState = .loading
    /// Bumped by the retry button to restart the load task for the same drawing.
    @State private var attempt = 0

    private enum LoadState: Equatable {
        case loading
        case loaded(UIImage)
        case failed
    }

    private struct LoadKey: Equatable {
        let revisionID: UUID
        let attempt: Int
    }

    var body: some View {
        // The plum square defines the size on its own, so the box is identical
        // whether the spinner, the retry glyph, or the loaded drawing is on top.
        // The box never changes size when the load finishes or fails.
        Rectangle()
            .fill(.paeoniaBackgroundPrimary)
            .aspectRatio(1, contentMode: .fit)
            .overlay { stateContent }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            // Offer the save button only once the drawing is on screen, so the
            // person can see what they're saving and we don't export a blank box.
            // Sits in the top-trailing corner so it stays clear of centered ink.
            .overlay(alignment: .topTrailing) {
                if case .loaded = loadState {
                    WidgetDrawingSaveButton(state: saveState, action: onSave)
                        .padding(PaeoniaSpacing.space4)
                }
            }
            // The finished drawing (and its save button) fades in over the spinner
            // instead of snapping into the box the moment the download lands.
            .animation(PaeoniaMotion.stateChange, value: loadState)
            .task(id: LoadKey(revisionID: item.id, attempt: attempt)) {
                await load()
            }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .tint(.paeoniaAccentPrimary)
        case .loaded(let uiImage):
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        case .failed:
            // The whole square is the retry target, so a failed drawing can be
            // tried again without scrolling it off screen and back.
            Button {
                loadState = .loading
                attempt += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.widgetHistoryThumbnailFailed))
        }
    }

    private func load() async {
        let data = await loader.thumbnailPNG(
            revisionID: item.id,
            mediaAssetID: item.mediaAssetID,
            canvasSide: item.canvasSide
        )
        // A cancelled load (the row left the screen, or a retry replaced it) says
        // nothing about whether the drawing can load.
        guard !Task.isCancelled else {
            return
        }
        if let data, let uiImage = UIImage(data: data) {
            loadState = .loaded(uiImage)
        } else {
            loadState = .failed
        }
    }
}

/// A small round button on a thumbnail's top edge: a download glyph that, once
/// the drawing is saved to the device, latches to a checkmark.
private struct WidgetDrawingSaveButton: View {
    let state: WidgetDrawingHistoryViewModel.SaveButtonState
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glyphSize: CGFloat = 32
    private static let hitTarget: CGFloat = 44

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: Self.glyphSize, height: Self.glyphSize)
                .glassEffect(.regular, in: Circle())
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Once saving starts the outcome is in motion; the saved state latches,
        // so the button only accepts a tap while idle.
        .disabled(state != .idle)
        .animation(PaeoniaMotion.stateChange, value: state)
        .accessibilityLabel(Text(
            state == .saved ? .widgetHistorySavedAccessibility : .widgetHistorySaveAccessibility
        ))
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .idle:
            Image(systemName: "arrow.down")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityHidden(true)
        case .saving:
            ProgressView()
                .controlSize(.small)
                .tint(.paeoniaAccentPrimary)
        case .saved:
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.paeoniaSuccess)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}
