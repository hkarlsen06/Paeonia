import SwiftUI
import UIKit

/// A starred widget drawing, shown large over the plum surface the drawings use everywhere.
/// The star stays on it, so the person can take it back from here.
struct FavoriteDrawingPreview: View {
    let favorite: FavoriteSummary
    let people: StoryPeople

    @State private var loader = WidgetRevisionThumbnailLoader(gateway: WidgetDrawingHistoryFactory.makeGateway())
    /// Keyed by the try, so a retry shows the spinner at once.
    @State private var load = ImageLoad<Int>.loading
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        NavigationStack {
            VStack(spacing: PaeoniaSpacing.space16) {
                picture
                caption
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(.favoritesRowDrawing))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.paeoniaBackgroundSecondary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text(.commonClose) }
                }
            }
            .favoriteToolbarItem(favorite.target, identifier: "favorite.preview.star")
        }
        .preferredColorScheme(.dark)
        .paeoniaBanner(bannerCenter)
        .task(id: attempt) { await loadDrawing() }
    }

    private var picture: some View {
        Rectangle()
            .fill(.paeoniaBackgroundPrimary)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 640)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                    .stroke(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image = load.image(for: attempt) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else if load.hasFailed(for: attempt) {
            Button {
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
        } else {
            ProgressView().tint(.paeoniaAccentPrimary)
        }
    }

    /// "You · 3 Oct 2026".
    private var caption: some View {
        let date = favorite.occurredAt.formatted(date: .abbreviated, time: .omitted)
        let parts = [people.name(ofUser: favorite.authorUserID), date].compactMap(\.self)
        return Text(parts.joined(separator: " · "))
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
    }

    private func loadDrawing() async {
        let attempt = attempt
        guard let mediaAssetID = favorite.mediaAssetID else {
            load = .failed(attempt)
            return
        }
        let side = favorite.bounds.map { CGFloat($0.canvasSide) } ?? WidgetDrawingViewModel.fallbackCanvasSide
        let data = await loader.exportPNG(revisionID: favorite.target.id, mediaAssetID: mediaAssetID, canvasSide: side)
        guard !Task.isCancelled else { return }
        // The drawing fades in over the spinner instead of replacing it in one frame.
        withAnimation(PaeoniaMotion.stateChange) {
            load = ImageLoad(data.flatMap(UIImage.init(data:)), for: attempt)
        }
    }
}
