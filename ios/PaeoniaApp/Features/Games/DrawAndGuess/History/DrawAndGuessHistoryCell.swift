import SwiftUI

/// One finished drawing in the grid: a square picture, the word, and who drew it
/// and when. A filled star shows when this person starred it, and a small badge
/// shows the guesser's reaction. A missed round looks the same as a solved one.
struct DrawAndGuessHistoryCell: View {
    let round: RemoteDrawAndGuessHistoryRound
    /// The partner's name, or "you".
    let drawerName: String
    let isStarred: Bool
    let drawings: GameHistoryDrawings

    @State private var image: UIImage?
    @State private var didFail = false

    init(
        round: RemoteDrawAndGuessHistoryRound,
        drawerName: String,
        isStarred: Bool,
        drawings: GameHistoryDrawings
    ) {
        self.round = round
        self.drawerName = drawerName
        self.isStarred = isStarred
        self.drawings = drawings
        // A picture seen before shows from the first frame, so scrolling back never flashes.
        _image = State(initialValue: GameDrawingThumbnails.cachedImage(for: round.drawingMediaAssetID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            thumbnail
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(DrawAndGuessAnswer.display(round.word))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(2)
                Text(.gamesDrawAndGuessHistoryCellCaption(drawerName, shortDate))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, PaeoniaSpacing.space4)
            .padding(.bottom, PaeoniaSpacing.space4)
        }
        .padding(PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: Self.shape)
        .contentShape(Self.shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private static let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

    private var shortDate: String {
        round.date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var accessibilityText: Text {
        let word = DrawAndGuessAnswer.display(round.word)
        return isStarred
            ? Text(.gamesDrawAndGuessHistoryCellStarredA11Y(word, drawerName))
            : Text(.gamesDrawAndGuessHistoryCellA11Y(word, drawerName))
    }

    /// The square keeps its size while the picture loads, so the grid never jumps.
    private var thumbnail: some View {
        Color.paeoniaBackgroundPrimary
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
            .overlay(alignment: .topTrailing) {
                if isStarred {
                    badge {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.paeoniaAccentPrimary)
                            .accessibilityHidden(true)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                StoredReactionBadge(target: .drawAndGuessRound(round.id))
                    .padding(PaeoniaSpacing.space8)
            }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .animation(PaeoniaMotion.stateChange, value: isStarred)
            .task(id: round.drawingMediaAssetID) { await loadPicture() }
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else if didFail {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
        }
    }

    private func badge(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(PaeoniaSpacing.space4)
            .frame(minWidth: 24, minHeight: 24)
            .background(.paeoniaBackgroundSecondary.opacity(0.85), in: Circle())
            .padding(PaeoniaSpacing.space8)
            .accessibilityHidden(true)
    }

    private func loadPicture() async {
        guard image == nil else { return }
        didFail = false
        let loaded = await drawings.thumbnail(for: round.drawingMediaAssetID)
        // A cell that scrolled away says nothing about whether the drawing can load.
        guard !Task.isCancelled else { return }
        image = loaded
        didFail = loaded == nil
    }
}
