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

/// The couple's content as an object in the room: a print in a cream frame, standing at
/// the main object's spot with a soft shadow on the floor, so the tiles still line up. In
/// the canvas's pixels.
struct GameHubFramedPicture: View {
    let picture: GameHubTilePicture

    private static let placement = GameHubPlacement(base: CGPoint(x: 512, y: 640), width: 440, aspect: 1)
    private static let border: CGFloat = 26

    var body: some View {
        let placement = Self.placement
        let inner = placement.width - 2 * Self.border
        ZStack {
            Ellipse()
                .fill(Color.paeoniaBackgroundSecondary.opacity(0.45))
                .frame(width: placement.width * 0.9, height: 30)
                .blur(radius: 12)
                .position(x: placement.base.x, y: placement.base.y - 4)
            GameChatPreviewContent(
                preview: picture.preview,
                drawings: picture.drawings,
                ownerUserID: picture.ownerUserID
            ) {
                Color.paeoniaBackgroundPrimary
            }
            .background(.paeoniaBackgroundPrimary)
            .scaleEffect(inner / GameChatPreview.side)
            .frame(width: inner, height: inner)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(Self.border)
            .background(PaeoniaPalette.blush, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .rotationEffect(.degrees(-2), anchor: .bottom)
            .position(x: placement.base.x, y: placement.base.y - placement.height / 2)
        }
        .allowsHitTesting(false)
    }
}
