import SwiftUI

/// This selection belongs to the sheet alone. Only confirmed sniffs go to Convex.
struct PiccanteSniffPicker: View {
    @Bindable var viewModel: PiccanteViewModel
    @Environment(\.dismiss) private var dismiss
    @AccessibilityPresentation(.controls) private var showsControls
    @State private var selected: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaeoniaSpacing.space20) {
                    Text(.piccanteSniffPrivate)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                    if let game = viewModel.game, let userID = viewModel.userID {
                        PiccanteBox(
                            game: game, shownBites: game.bites.count, revealsChilis: false,
                            selected: selected, partnerSelected: nil, pendingTile: nil,
                            player: { $0 == userID ? viewModel.meInfo : viewModel.partnerInfo },
                            select: { selected = $0 }, canSelect: viewModel.canAct,
                            selectable: { PiccanteRules.canSniff($0, in: game, userID: userID) },
                            tileIdentifierPrefix: "piccante.sniff.tile")
                        if showsControls { nativeTiles(game, userID: userID) }
                    }
                }
                .padding(PaeoniaSpacing.screenHorizontalPadding)
                .paeoniaReadableWidth()
            }
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle(Text(.piccanteSniffAction))
            .toolbar { actions }
        }
    }

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task {
                    await viewModel.act(.sniff, tile: selected)
                    dismiss()
                }
            } label: {
                Text(.piccanteSniffAction)
            }
            .disabled(selected == nil || viewModel.isSaving || !viewModel.canAct)
            .accessibilityIdentifier("piccante.sniff.confirm")
        }
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Text(.commonCancel) }
        }
    }

    private func nativeTiles(_ game: RemotePiccanteGame, userID: UUID) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            ForEach(0..<((game.size ?? 3) * (game.size ?? 3)), id: \.self) { tile in
                if PiccanteRules.canSniff(tile, in: game, userID: userID) {
                    Button { selected = tile } label: {
                        HStack {
                            Text(.piccanteTilePosition(tile / (game.size ?? 3) + 1, tile % (game.size ?? 3) + 1))
                            Spacer()
                            if selected == tile { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                    .accessibilityAddTraits(selected == tile ? .isSelected : [])
                    .accessibilityIdentifier("piccante.sniff.list.\(tile)")
                }
            }
        }
    }
}
