import SwiftUI

/// A game's latest public content (`GameChatPreview`) in a 240-point square. The chat
/// thumbnail and the hub's tiles both draw it, scaled to their size, on their own background. `fallback` shows
/// while a drawing loads or when it can't.
struct GameChatPreviewContent<Fallback: View>: View {
    let preview: GameChatPreview
    let drawings: GameHistoryDrawings?
    /// Whose Games store a drawing's download is written to, so a finished download reloads.
    let ownerUserID: UUID?
    let participants: GameParticipants
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        content
            .frame(width: GameChatPreview.side, height: GameChatPreview.side)
    }

    @ViewBuilder private var content: some View {
        switch preview {
        case .board(let board):
            GameChatBoardThumbnail(kind: board.kind, moves: board.moves, me: board.me, colors: board.colors)
                .environment(\.gameBoardShowsControls, false)
                .padding(PaeoniaSpacing.space16)
        case .drawing(let id):
            drawing([id])
        case .creature(let ids):
            drawing(ids)
        case .photo(let id):
            MemoryMediaImageView(mediaAssetID: id, height: GameChatPreview.side, cornerRadius: 0, allowsViewing: false)
        case .words(let mine, let theirs):
            VStack(spacing: PaeoniaSpacing.space12) {
                word(mine, color: .boardGameMine).rotationEffect(.degrees(-5))
                word(theirs, color: .boardGamePartner).rotationEffect(.degrees(5))
            }.padding(PaeoniaSpacing.space24)
        case .story(let text):
            Text(verbatim: text)
                .font(.system(size: 25, design: .serif))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(PaeoniaSpacing.space24)
                .clipped()
        case .piccante(let game):
            PiccanteBox(
                game: game, shownBites: game.bites.count, revealsChilis: game.phase == .finished,
                selected: nil, partnerSelected: nil, pendingTile: nil,
                player: {
                    let mine = $0 == ownerUserID
                    let name = mine ? participants.currentName : participants.partnerName
                    return BoardGamePlayerInfo(
                        name: name,
                        photoAssetID: mine ? participants.currentPhotoAssetID : participants.partnerPhotoAssetID,
                        style: BoardPieceStyle(
                            color: mine ? .boardGameMine : .boardGamePartner, mark: nil,
                            initial: BoardPieceStyle.initial(of: name), owner: mine ? .one : .two))
                }, select: { _ in }, showsOwnChili: false
            )
            .padding(PaeoniaSpacing.space16)
        case .scale(let spot, let guess):
            ConsensioScale(
                subject: "", leftEnd: "", rightEnd: "",
                pins: [
                    .init(id: "spot", position: spot, style: styles.one),
                    .init(id: "guess", position: guess, style: styles.two),
                ], thread: .init(from: guess, to: spot, progress: 1)
            )
            .padding(PaeoniaSpacing.space16)
        }
    }

    private func drawing(_ ids: [UUID]) -> some View {
        GameChatDrawingThumbnail(assetIDs: ids, drawings: drawings, ownerUserID: ownerUserID) {
            fallback().transaction { $0.disablesAnimations = true }
        }
    }

    private func word(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .padding(PaeoniaSpacing.space12)
            .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
    }

    private var styles: BoardPieceStyles { GameChatBoardThumbnail.styles(me: .one) }
}

private struct GameChatDrawingThumbnail<Fallback: View>: View {
    let assetIDs: [UUID]
    let drawings: GameHistoryDrawings?
    let ownerUserID: UUID?
    @ViewBuilder let fallback: () -> Fallback
    @Environment(\.scenePhase) private var scenePhase
    @State private var images: [UIImage] = []

    private struct LoadKey: Hashable {
        let assetIDs: [UUID]
        let isActive: Bool
    }

    var body: some View {
        Color.clear.overlay {
            if images.count == assetIDs.count, !images.isEmpty {
                VStack(spacing: 0) {
                    ForEach(images.indices, id: \.self) { index in
                        Image(uiImage: images[index]).resizable().scaledToFit()
                            .frame(height: GameChatPreview.side / CGFloat(images.count))
                            .accessibilityHidden(true)
                    }
                }
            } else {
                fallback()
            }
        }
        .clipped()
        .task(id: LoadKey(assetIDs: assetIDs, isActive: scenePhase == .active)) {
            images = []
            let changes = LocalStoreChanges.changes(in: .games)
            await load()
            for await change in changes where change.ownerUserID == ownerUserID {
                if images.count != assetIDs.count { await load() }
            }
        }
    }

    private func load() async {
        var loaded: [UIImage] = []
        for id in assetIDs {
            guard let image = await drawings?.thumbnail(for: id), !Task.isCancelled else { return }
            loaded.append(image)
        }
        guard !Task.isCancelled else { return }
        images = loaded
    }
}
