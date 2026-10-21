import SwiftUI

/// One finished creature in the grid: the head, body and legs stacked as one
/// tall picture, with "Creature 12 · Oct 12" under it. A filled star shows when
/// this person starred it.
struct ExquisiteCorpseHistoryCell: View {
    let figure: RemoteExquisiteCorpseFigure
    let partnerName: String
    let isStarred: Bool
    let drawings: GameHistoryDrawings

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            picture
            Text(.exquisiteCorpseHistoryCellCaption(figure.number, shortDate))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(2)
                .padding(.horizontal, PaeoniaSpacing.space4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var shortDate: String {
        (figure.finishedAt ?? figure.createdAt).formatted(.dateTime.day().month(.abbreviated))
    }

    private var accessibilityText: Text {
        isStarred
            ? Text(.exquisiteCorpseHistoryCellStarredA11Y(figure.number, partnerName))
            : Text(.exquisiteCorpseHistoryCellA11Y(figure.number, partnerName))
    }

    /// Three squares in a column. Each keeps its size while its drawing loads, so
    /// the grid never jumps.
    private var picture: some View {
        VStack(spacing: 0) {
            ForEach(ExquisiteCorpsePartKind.allCases, id: \.self) { kind in
                ExquisiteCorpseHistoryPartPicture(
                    mediaAssetID: figure.part(at: kind.rawValue)?.drawingMediaAssetID,
                    drawings: drawings
                )
            }
        }
        .background(.paeoniaBackgroundPrimary)
        .overlay { folds }
        .overlay(alignment: .topTrailing) {
            if isStarred {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .padding(PaeoniaSpacing.space4)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(.paeoniaBackgroundSecondary.opacity(0.85), in: Circle())
                    .padding(PaeoniaSpacing.space8)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            StoredReactionBadge(target: .exquisiteCorpseFigure(figure.id))
                .padding(PaeoniaSpacing.space8)
        }
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .animation(PaeoniaMotion.stateChange, value: isStarred)
    }

    /// A hairline at each fold, so the parts stay readable.
    private var folds: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            hairline
            Spacer(minLength: 0)
            hairline
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var hairline: some View {
        Rectangle()
            .fill(.paeoniaTextTertiary.opacity(0.3))
            .frame(height: PaeoniaRadius.strokeHairline)
    }
}

/// One square of a creature: its drawing, a spinner while it loads, or a quiet
/// icon when it can't be loaded.
private struct ExquisiteCorpseHistoryPartPicture: View {
    let mediaAssetID: UUID?
    let drawings: GameHistoryDrawings

    @State private var image: UIImage?
    @State private var didFail = false

    init(mediaAssetID: UUID?, drawings: GameHistoryDrawings) {
        self.mediaAssetID = mediaAssetID
        self.drawings = drawings
        // A picture seen before shows from the first frame, so scrolling back never flashes.
        _image = State(initialValue: mediaAssetID.flatMap(GameDrawingThumbnails.cachedImage(for:)))
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .task(id: mediaAssetID) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else if didFail {
            Image(systemName: "photo")
                .font(.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(.paeoniaAccentPrimary)
        }
    }

    private func load() async {
        guard image == nil else { return }
        guard let mediaAssetID else {
            didFail = true
            return
        }
        didFail = false
        let loaded = await drawings.thumbnail(for: mediaAssetID)
        // A cell that scrolled away says nothing about whether the drawing can load.
        guard !Task.isCancelled else { return }
        image = loaded
        didFail = loaded == nil
    }
}
