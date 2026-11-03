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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: size), spacing: 10) {
            ForEach(0..<(size * size), id: \.self) { tile in
                Button {
                    select(tile)
                } label: {
                    chocolate(tile)
                }
                .buttonStyle(.plain)
                .disabled(!canSelect || eaten.contains { $0.tile == tile })
                .accessibilityLabel(label(tile))
                .accessibilityAddTraits(selected == tile ? [.isSelected] : [])
                .accessibilityIdentifier("piccante.tile.\(tile)")
            }
        }
        .padding(PaeoniaSpacing.space16)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.78, green: 0.52, blue: 0.33), Color(red: 0.37, green: 0.19, blue: 0.17)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26).strokeBorder(Color.paeoniaInkGold.opacity(0.65), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: selected)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: revealsChilis)
    }

    private func chocolate(_ tile: Int) -> some View {
        let bite = eaten.firstIndex { $0.tile == tile }
        let chilis = revealsChilis ? game.chilis.filter { $0.tile == tile } : []
        let own = showsOwnChili && game.myChili == tile
        let lifted = selected == tile || partnerSelected == tile
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.24))
            RoundedRectangle(cornerRadius: 11)
                .fill(
                    LinearGradient(
                        colors: chocolateColors(tile, eaten: bite != nil, burns: !chilis.isEmpty),
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12), lineWidth: 2).padding(8)
                }
                .shadow(color: lifted ? .black.opacity(0.5) : .clear, radius: 5, y: 6)
            if !chilis.isEmpty {
                VStack(spacing: 2) {
                    Text(verbatim: "🌶️")
                        .foregroundStyle(Color.paeoniaInkGold)
                        .font(.title3)
                        .accessibilityHidden(true)
                    HStack(spacing: 2) {
                        ForEach(chilis.indices, id: \.self) { index in
                            BoardMarkView(style: style(chilis[index].userID))
                                .frame(width: 18, height: 18)
                        }
                    }
                }
            } else if bite != nil {
                PiccanteFilling()
                    .fill(
                        LinearGradient(
                            colors: chocolateColors(tile, eaten: true, burns: false), startPoint: .top,
                            endPoint: .bottom)
                    )
                    .padding(9)
                    .overlay { PiccanteCrack().stroke(Color.white.opacity(0.35), lineWidth: 2).padding(7) }
                    .accessibilityHidden(true)
            } else if own {
                Text(verbatim: "🌶️")
                    .foregroundStyle(Color.paeoniaInkGold)
                    .font(.title3)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: tile.isMultiple(of: 2) ? "heart.fill" : "leaf.fill")
                    .foregroundStyle(Color.white.opacity(0.15))
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            if pendingTile == tile { ProgressView().tint(.white) }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            if let bite {
                Text(verbatim: "\(bite + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if lifted {
                Image(systemName: selected == tile ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white, Color.black.opacity(0.7))
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                selected == tile ? Color.paeoniaAccentPrimary : partnerSelected == tile ? .paeoniaInkLavender : .clear,
                lineWidth: 3)
        }
        .offset(y: lifted && !reduceMotion ? -7 : 0)
        .scaleEffect(lifted && !reduceMotion ? 1.05 : 1)
        .accessibilityElement(children: .ignore)
    }
    private func chocolateColors(_ tile: Int, eaten: Bool, burns: Bool) -> [Color] {
        if burns { return [.red.opacity(0.8), Color(red: 0.4, green: 0.06, blue: 0.1)] }
        if eaten {
            let colors: [Color] = [.paeoniaInkGold, .paeoniaAccentPrimary, .paeoniaInkLavender]
            let flavor = PiccanteRules.flavorIndex(gameID: game.id, number: game.gameNumber, tile: tile)
            return [colors[flavor % colors.count], Color(red: 0.27, green: 0.12, blue: 0.1)]
        }
        return [Color(red: 0.48, green: 0.27, blue: 0.19), Color(red: 0.24, green: 0.1, blue: 0.09)]
    }
    func label(_ tile: Int) -> String {
        var words = [String(localized: .piccanteTilePosition(tile / size + 1, tile % size + 1))]
        if let index = eaten.firstIndex(where: { $0.tile == tile }) {
            words.append(
                String(
                    localized: .piccanteTileEaten(
                        index + 1,
                        String(localized: PiccanteRules.flavor(gameID: game.id, number: game.gameNumber, tile: tile)))))
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

nonisolated private struct PiccanteFilling: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.28))
            path.addLine(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.15))
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.88),
                control: CGPoint(x: rect.width * 1.05, y: rect.height))
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.25), control: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}
nonisolated private struct PiccanteCrack: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.3))
            path.addLines([
                CGPoint(x: rect.width * 0.35, y: rect.height * 0.1),
                CGPoint(x: rect.width * 0.55, y: rect.height * 0.35), CGPoint(x: rect.width, y: rect.height * 0.15),
            ])
        }
    }
}
