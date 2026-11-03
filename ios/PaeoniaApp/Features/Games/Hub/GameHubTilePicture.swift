import SwiftUI

/// The couple's latest content for one game, which its hub tile shows in place of the
/// game's objects (`GameHubArtwork`). Only what `GameChatPreviewLoader` allows: public
/// boards and revealed content.
struct GameHubTilePicture {
    let preview: GameChatPreview
    let drawings: GameHistoryDrawings
    let ownerUserID: UUID
}

extension EnvironmentValues {
    @Entry var gameHubTilePicture: GameHubTilePicture?
}

extension View {
    /// Gives a hub tile the couple's content for `kind`, read again after every change to
    /// the Games store. Without any, the tile keeps its objects and beat.
    func gameHubTilePicture(for kind: GameKind, viewModel: GamesViewModel) -> some View {
        modifier(GameHubTilePictureLoader(kind: kind, viewModel: viewModel))
    }
}

private struct GameHubTilePictureLoader: ViewModifier {
    let kind: GameKind
    let viewModel: GamesViewModel
    @State private var picture: GameHubTilePicture?

    func body(content: Content) -> some View {
        content
            .environment(\.gameHubTilePicture, picture)
            .task(id: viewModel.currentUserID) {
                let owner = viewModel.currentUserID
                let changes = LocalStoreChanges.changes(in: .games, .pendingOperations)
                await reload()
                for await change in changes where change.ownerUserID == owner {
                    await reload()
                }
            }
    }

    private func reload() async {
        let next = await viewModel.tilePicture(for: kind)
        guard !Task.isCancelled else { return }
        picture = next
    }
}

/// The couple's content on a hub tile, in the canvas's pixels.
struct GameHubTileContent: View {
    let picture: GameHubTilePicture
    let tint: Color?

    var body: some View {
        let side: CGFloat = 640
        let base = CGPoint(x: 512, y: 676)
        let shape = RoundedRectangle(cornerRadius: 64, style: .continuous)
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: side * 0.85, height: 40)
                .blur(radius: 16)
                .position(x: base.x, y: base.y + 6)
            GameChatPreviewContent(
                preview: picture.preview,
                drawings: picture.drawings,
                ownerUserID: picture.ownerUserID
            ) {
                Color.clear
            }
            .scaleEffect(side / GameChatPreview.side)
            .frame(width: side, height: side)
            .background {
                ZStack {
                    Color.paeoniaBackgroundPrimary
                    (tint ?? .clear).opacity(0.62)
                    LinearGradient(
                        colors: [.white.opacity(0.12), .black.opacity(0.18)], startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
            .position(x: base.x, y: base.y - side / 2)
        }
        .allowsHitTesting(false)
    }
}
