import SwiftUI

struct PiccanteBox: View {
    let game: RemotePiccanteGame
    let shownBites: Int
    let revealsChilis: Bool
    let selected: Int?
    let partnerSelected: Int?
    let pendingTile: Int?
    let player: (UUID) -> BoardGamePlayerInfo
    let select: (Int) -> Void
    var canSelect = false
    var showsOwnChili = true
    var showsSniff = true
    var revealsBurn: Bool?
    var burnShake = 0
    var currentUserID: UUID?
    var selectable: ((Int) -> Bool)?
    var tileIdentifierPrefix = "piccante.tile"

    private var lastPartnerBite: PiccanteBite? {
        guard let currentUserID, selected == nil, game.phase == .biting else { return nil }
        return eaten.last { $0.userID != currentUserID }
    }
    private var burnIsVisible: Bool { revealsBurn ?? revealsChilis }

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
                        variety: PiccanteRules.variety(gameID: game.id, number: game.gameNumber, tile: tile),
                        isEaten: eaten.contains { $0.tile == tile },
                        chilis: revealsChilis
                            ? game.chilis.filter { $0.tile == tile }.map { player($0.userID) } : [],
                        isOwnChili: showsOwnChili && game.myChili == tile && (game.phase != .finished || revealsChilis),
                        isHiding: game.phase == .hiding && selected == tile,
                        isOpening: !burnIsVisible && game.phase == .finished && game.bites.last?.tile == tile,
                        isBurned: burnIsVisible && game.phase == .finished && game.bites.last?.tile == tile,
                        isSelected: selected == tile, isPartnerSelected: partnerSelected == tile,
                        isPending: pendingTile == tile,
                        sniff: showsSniff && game.mySniff?.tile == tile ? game.mySniff : nil,
                        lastBiter: lastPartnerBite?.tile == tile ? lastPartnerBite.map { player($0.userID) } : nil,
                        burnShake: burnShake)
                }
                .buttonStyle(PiccanteTileButtonStyle())
                .disabled(!canSelect || eaten.contains { $0.tile == tile } || selectable?(tile) == false)
                .accessibilityLabel(label(tile))
                .accessibilityAddTraits(selected == tile ? [.isSelected] : [])
                .accessibilityIdentifier("\(tileIdentifierPrefix).\(tile)")
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
        if eaten.contains(where: { $0.tile == tile }) {
            if game.phase == .finished && game.bites.last?.tile == tile {
                words.append(String(localized: burnIsVisible
                    ? .piccanteTileBurned : .piccanteOpeningChocolate))
            } else {
                words.append(String(localized: .piccanteTileEaten))
            }
        }
        if !eaten.contains(where: { $0.tile == tile }) {
            let variety = PiccanteRules.variety(gameID: game.id, number: game.gameNumber, tile: tile)
            words.append(String(localized: variety.name))
        }
        if let lastPartnerBite, lastPartnerBite.tile == tile {
            words.append(String(localized: .piccantePartnerLastBite(player(lastPartnerBite.userID).name)))
        }
        if showsSniff, let sniff = game.mySniff, sniff.tile == tile, !eaten.contains(where: { $0.tile == tile }) {
            words.append(String(localized: sniff.hasChili ? .piccanteSniffMarkedHot : .piccanteSniffMarkedSafe))
        }
        if showsOwnChili && game.myChili == tile { words.append(String(localized: .piccanteYourChili)) }
        if revealsChilis {
            for chili in game.chilis where chili.tile == tile {
                words.append(String(localized: .piccanteChiliOwner(player(chili.userID).name)))
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
