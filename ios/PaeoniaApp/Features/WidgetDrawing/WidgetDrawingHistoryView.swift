import SwiftUI
import UIKit

/// Builds the gateway the history timeline reads through, falling back to a
/// no-op when no Supabase client is configured (previews, signed-out states).
nonisolated enum WidgetDrawingHistoryFactory {
    static func makeGateway() -> any WidgetCanvasGateway {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return NoOpWidgetCanvasGateway()
        }
        return LiveSupabaseWidgetCanvasGateway(client: client)
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

    @ViewBuilder
    private var content: some View {
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
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space20)
        }
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
    @State private var imageData: Data?

    var body: some View {
        // The plum square defines the size on its own, so the box is identical
        // whether the spinner or the loaded drawing is on top — no layout shift
        // when the thumbnail finishes loading.
        Rectangle()
            .fill(.paeoniaBackgroundPrimary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .tint(.paeoniaAccentPrimary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            // Offer the save button only once the drawing is on screen, so the
            // person can see what they're saving and we don't export a blank box.
            // Sits in the top-trailing corner so it stays clear of centered ink.
            .overlay(alignment: .topTrailing) {
                if imageData != nil {
                    WidgetDrawingSaveButton(state: saveState, action: onSave)
                        .padding(PaeoniaSpacing.space4)
                }
            }
            .task(id: item.id) {
                imageData = await loader.thumbnailPNG(
                    revisionID: item.id,
                    mediaAssetID: item.mediaAssetID,
                    canvasSide: item.canvasSide
                )
            }
    }
}

/// A small round button on a thumbnail's top edge: a download glyph that, once
/// the drawing is saved to the device, latches to a checkmark.
private struct WidgetDrawingSaveButton: View {
    let state: WidgetDrawingHistoryViewModel.SaveButtonState
    let action: () -> Void

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
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}
