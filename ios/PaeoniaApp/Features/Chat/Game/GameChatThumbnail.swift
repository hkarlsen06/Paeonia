import SwiftUI

struct GameChatThumbnail: View {
    let kind: GameKind
    @Environment(\.threadChatContext) private var context
    @State private var preview: GameChatPreview?

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: 240, height: 240)
                .scaleEffect(geometry.size.width / 240, anchor: .topLeading)
        }
        .background(.paeoniaBackgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: context.participants.currentUserID) {
            preview = nil
            let changes = LocalStoreChanges.changes(in: .games, .pendingOperations)
            await reload()
            for await change in changes where change.ownerUserID == context.participants.currentUserID {
                await reload()
            }
        }
    }

    private func reload() async {
        let next = await context.gamePreview?(kind)
        guard !Task.isCancelled else { return }
        preview = next
    }

    @ViewBuilder private var content: some View {
        switch preview {
        case .board(let board):
            GameChatBoardThumbnail(kind: board.kind, moves: board.moves, me: board.me, colors: board.colors)
                .padding(PaeoniaSpacing.space16)
        case .drawing(let id):
            GameChatDrawingThumbnail(assetIDs: [id], fallback: artwork)
        case .creature(let ids):
            GameChatDrawingThumbnail(assetIDs: ids, fallback: artwork)
        case .photo(let id):
            MemoryMediaImageView(mediaAssetID: id, height: 240, cornerRadius: 0, allowsViewing: false)
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
                .background(.paeoniaSurfaceSecondary)
                .clipped()
        case .scale(let spot, let guess):
            ConsensioScale(
                subject: "", leftEnd: "", rightEnd: "",
                pins: [
                    .init(id: "spot", position: spot, style: styles.one),
                    .init(id: "guess", position: guess, style: styles.two),
                ], thread: .init(from: guess, to: spot, progress: 1)
            )
            .padding(PaeoniaSpacing.space16)
        case nil:
            artwork
                .transaction { $0.disablesAnimations = true }
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

    @ViewBuilder private var artwork: some View {
        switch kind {
        case .connectFour: ConnectFourHubArtwork()
        case .dotsAndBoxes: DotsAndBoxesHubArtwork()
        case .ultimateTicTacToe: UltimateTicTacToeHubArtwork()
        case .ludo: LudoHubArtwork()
        case .drawAndGuess: DrawAndGuessHubArtwork()
        case .exquisiteCorpse: ExquisiteCorpseHubArtwork()
        case .mindMeld: MindMeldHubArtwork()
        case .consensio: ConsensioHubArtwork()
        case .guessMySpot: GuessMySpotHubArtwork()
        case .storyChain: StoryChainHubArtwork()
        }
    }

    private var styles: BoardPieceStyles { GameChatBoardThumbnail.styles(me: .one) }
}

private struct GameChatDrawingThumbnail<Fallback: View>: View {
    let assetIDs: [UUID]
    let fallback: Fallback
    @Environment(\.threadChatContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var images: [UIImage] = []

    private struct LoadKey: Hashable {
        let assetIDs: [UUID]
        let isActive: Bool
    }

    var body: some View {
        Color.paeoniaBackgroundPrimary.overlay {
            if images.count == assetIDs.count, !images.isEmpty {
                VStack(spacing: 0) {
                    ForEach(images.indices, id: \.self) { index in
                        Image(uiImage: images[index]).resizable().scaledToFit()
                            .frame(height: 240 / CGFloat(images.count))
                            .accessibilityHidden(true)
                    }
                }
            } else {
                fallback.transaction { $0.disablesAnimations = true }
            }
        }
        .clipped()
        .task(id: LoadKey(assetIDs: assetIDs, isActive: scenePhase == .active)) {
            images = []
            let changes = LocalStoreChanges.changes(in: .games)
            await load()
            for await change in changes where change.ownerUserID == context.participants.currentUserID {
                if images.count != assetIDs.count { await load() }
            }
        }
    }

    private func load() async {
        var loaded: [UIImage] = []
        for id in assetIDs {
            guard let image = await context.gameDrawings?.thumbnail(for: id), !Task.isCancelled else { return }
            loaded.append(image)
        }
        guard !Task.isCancelled else { return }
        images = loaded
    }
}
