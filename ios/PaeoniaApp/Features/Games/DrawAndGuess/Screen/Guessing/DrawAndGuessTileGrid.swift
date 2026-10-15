import SwiftUI

/// The letter tiles, six to a row. A tile that sits in a slot leaves an empty cell,
/// so the grid never reflows.
struct DrawAndGuessTileGrid: View {
    let viewModel: DrawAndGuessViewModel
    let namespace: Namespace.ID

    @State private var availableWidth: CGFloat = 340
    @ScaledMetric(relativeTo: .title2) private var tileCap: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gap = PaeoniaSpacing.space8
    private static let maxCap: CGFloat = 64

    private var side: CGFloat {
        let cap = min(tileCap, Self.maxCap)
        let columns = CGFloat(DrawAndGuessTiles.rowSize)
        return min(cap, ((availableWidth - Self.gap * (columns - 1)) / columns).rounded(.down))
    }

    private var rows: [[DrawAndGuessTile]] {
        stride(from: 0, to: viewModel.tiles.count, by: DrawAndGuessTiles.rowSize).map {
            Array(viewModel.tiles[$0..<min($0 + DrawAndGuessTiles.rowSize, viewModel.tiles.count)])
        }
    }

    var body: some View {
        let used = viewModel.slots.placedTileIDs
        VStack(spacing: Self.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.gap) {
                    ForEach(row) { tile in
                        cell(tile, isUsed: used.contains(tile.id))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : .spring(duration: 0.16), value: used)
        .accessibilityIdentifier("draw.guess.tiles")
    }

    private func cell(_ tile: DrawAndGuessTile, isUsed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                .fill(.paeoniaSurfaceSecondary)
            if !isUsed {
                Button {
                    place(tile)
                } label: {
                    DrawAndGuessTileFace(letter: tile.letter)
                        .frame(width: side, height: side)
                        .modifier(DrawAndGuessTileFlight(id: tile.id, namespace: namespace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.gamesDrawAndGuessTileLabel(String(tile.letter))))
            }
        }
        .frame(width: side, height: side)
    }

    private func place(_ tile: DrawAndGuessTile) {
        guard !viewModel.isShowingWrongGuess else { return }
        let slot = viewModel.slots.slots.first { !$0.isGap && $0.tile == nil }
        PaeoniaHaptics.selection()
        GameSound.tap.play(volume: 0.8)
        viewModel.placeTile(tile)
        if let slot, viewModel.slots.slots.indices.contains(slot.id), viewModel.slots.slots[slot.id].tile != nil {
            let number = viewModel.slots.slots.prefix(slot.id + 1).count { !$0.isGap }
            AccessibilityNotification.Announcement(
                String(localized: .gamesDrawAndGuessGuessPlaced(String(tile.letter), number))
            ).post()
        }
    }
}
