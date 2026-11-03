import SwiftUI

struct GameChatThumbnail: View {
    let kind: GameKind
    @Environment(\.threadChatContext) private var context
    @State private var preview: GameChatPreview?

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: GameChatPreview.side, height: GameChatPreview.side)
                .scaleEffect(geometry.size.width / GameChatPreview.side, anchor: .topLeading)
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
        if let preview {
            GameChatPreviewContent(
                preview: preview,
                drawings: context.gameDrawings,
                ownerUserID: context.participants.currentUserID
            ) {
                artwork
            }
        } else {
            artwork
                .transaction { $0.disablesAnimations = true }
        }
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
}
