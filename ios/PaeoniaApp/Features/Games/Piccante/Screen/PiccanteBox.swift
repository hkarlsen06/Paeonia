import SwiftUI

struct PiccanteBox: View {
    let game: RemotePiccanteGame
    let shownBites: Int
    let revealsChilis: Bool
    let selected: Int?
    let partnerSelected: Int?
    let pendingTile: Int?
    let style: (UUID) -> BoardPieceStyle
    let select: (Int) -> Void
    var canSelect = false
    var showsOwnChili = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var size: Int { game.size ?? 3 }
    private var eaten: [PiccanteBite] { Array(game.bites.prefix(shownBites)) }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: PaeoniaSpacing.space8), count: size),
            spacing: PaeoniaSpacing.space8
        ) {
            ForEach(0..<(size * size), id: \.self) { tile in
                Button {
                    select(tile)
                } label: {
                    PiccanteTile(
                        tile: tile,
                        bite: eaten.firstIndex { $0.tile == tile }.map { $0 + 1 },
                        chilis: revealsChilis
                            ? game.chilis.filter { $0.tile == tile }.map { style($0.userID) } : [],
                        isOwnChili: showsOwnChili && game.myChili == tile,
                        isHiding: game.phase == .hiding && selected == tile,
                        isOpening: !revealsChilis && game.phase == .finished && game.bites.last?.tile == tile,
                        isBurned: revealsChilis && game.phase == .finished && game.bites.last?.tile == tile,
                        isSelected: selected == tile, isPartnerSelected: partnerSelected == tile,
                        isPending: pendingTile == tile)
                }
                .buttonStyle(PiccanteTileButtonStyle())
                .disabled(!canSelect || eaten.contains { $0.tile == tile })
                .accessibilityLabel(label(tile))
                .accessibilityAddTraits(selected == tile ? [.isSelected] : [])
                .accessibilityIdentifier("piccante.tile.\(tile)")
            }
        }
        .padding(PaeoniaSpacing.space12)
        .background {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius24)
                .fill(Color.paeoniaInkLavender.mix(with: .paeoniaSurfacePrimary, by: 0.75).gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius24)
                        .strokeBorder(Color.paeoniaInkLavender.opacity(0.65), lineWidth: 2)
                    RoundedRectangle(cornerRadius: PaeoniaRadius.radius20)
                        .strokeBorder(Color.paeoniaBackgroundSecondary.opacity(0.5), lineWidth: 2)
                        .padding(5)
                }
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: selected)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: partnerSelected)
    }

    func label(_ tile: Int) -> String {
        var words = [String(localized: .piccanteTilePosition(tile / size + 1, tile % size + 1))]
        if let index = eaten.firstIndex(where: { $0.tile == tile }) {
            if game.phase == .finished && game.bites.last?.tile == tile {
                words.append(String(localized: revealsChilis
                    ? .piccanteTileBurned(index + 1) : .piccanteOpeningChocolate))
            } else {
                let flavor = String(
                    localized: PiccanteRules.flavor(
                        gameID: game.id, number: game.gameNumber, tile: tile))
                words.append(String(localized: .piccanteTileEaten(index + 1, flavor)))
            }
        }
        if showsOwnChili && game.myChili == tile { words.append(String(localized: .piccanteYourChili)) }
        if revealsChilis {
            for chili in game.chilis where chili.tile == tile {
                words.append(String(localized: .piccanteChiliOwner(style(chili.userID).initial)))
            }
        }
        if selected == tile { words.append(String(localized: .piccanteSelected)) }
        if partnerSelected == tile { words.append(String(localized: .piccantePartnerLifted)) }
        return words.joined(separator: ". ")
    }
}

/// Completed pieces keep their contrast when they stop accepting taps.
private struct PiccanteTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
