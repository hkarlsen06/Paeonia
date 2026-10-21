import SwiftUI
import UIKit

/// A starred widget drawing, shown large over the plum surface the drawings use everywhere.
/// The star stays on it, so the person can take it back from here.
struct FavoriteDrawingPreview: View {
    let favorite: FavoriteSummary
    let people: StoryPeople

    @State private var loader = WidgetRevisionThumbnailLoader(gateway: WidgetDrawingHistoryFactory.makeGateway())
    @State private var image: UIImage?
    @State private var didFail = false
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
        .paeoniaTopBanner(bannerCenter)
        .task(id: attempt) { await load() }
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
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else if didFail {
            Button {
                didFail = false
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

    private func load() async {
        guard let mediaAssetID = favorite.mediaAssetID else {
            didFail = true
            return
        }
        let side = favorite.bounds.map { CGFloat($0.canvasSide) } ?? WidgetDrawingViewModel.fallbackCanvasSide
        let data = await loader.exportPNG(revisionID: favorite.target.id, mediaAssetID: mediaAssetID, canvasSide: side)
        guard !Task.isCancelled else { return }
        if let data, let loaded = UIImage(data: data) {
            image = loaded
        } else {
            didFail = true
        }
    }
}
