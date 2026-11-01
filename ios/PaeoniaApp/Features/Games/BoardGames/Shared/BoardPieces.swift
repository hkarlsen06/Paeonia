import SwiftUI

extension Color {
    /// My pieces on this phone, the color of my avatar in Draw & Guess.
    static let boardGameMine = Color.paeoniaPartnerOne
    /// My partner's pieces. Lavender instead of the second pink, so the two
    /// sides read apart at a glance on a busy board.
    static let boardGamePartner = Color.paeoniaInkLavender
}

/// How one player's pieces look on this phone: `.boardGameMine` for mine and
/// `.boardGamePartner` for my partner's.
struct BoardPieceStyle: Equatable {
    let color: Color
    /// The player's drawn mark as a template image, or nil to show `initial`.
    let mark: UIImage?
    /// The first letter of the player's display name, uppercased.
    let initial: String
    /// A stable shape distinguishes owners even when their custom marks match.
    var owner: BoardPlayer

    static func == (lhs: BoardPieceStyle, rhs: BoardPieceStyle) -> Bool {
        lhs.color == rhs.color && lhs.mark === rhs.mark && lhs.initial == rhs.initial && lhs.owner == rhs.owner
    }

    nonisolated static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }
}

/// Both players' styles, by board player.
struct BoardPieceStyles: Equatable {
    let one: BoardPieceStyle
    let two: BoardPieceStyle

    init(one: BoardPieceStyle, two: BoardPieceStyle) {
        var one = one
        var two = two
        one.owner = .one
        two.owner = .two
        self.one = one
        self.two = two
    }

    subscript(player: BoardPlayer) -> BoardPieceStyle {
        player == .one ? one : two
    }
}

/// The newest move on the board, so the board can animate it. A board animates
/// a move when `number` changes. A move it never saw arrive, such as one already
/// on the board when the screen opens, just shows.
nonisolated struct BoardMoveEvent: Equatable, Sendable {
    /// 1 for the first move of the game.
    let number: Int
    let move: Int
    let player: BoardPlayer
    let isMine: Bool
}

/// A player's mark, tinted. The drawn mark when there is one, otherwise the
/// initial in a rounded bold face. It fills the space it is given, so the
/// caller sizes it.
struct BoardMarkView: View {
    let style: BoardPieceStyle
    var tint: Color = .paeoniaTextPrimary

    @Environment(\.showsBoardOwnerSymbols) private var showsOwner

    /// With the owner shape on, the mark shrinks toward one corner so the shape
    /// sits in the free corner instead of covering the drawing.
    private static let markScaleWithOwner: CGFloat = 0.74
    private static let ownerScale: CGFloat = 0.24

    var body: some View {
        GeometryReader { proxy in
            let scale = showsOwner ? Self.markScaleWithOwner : 1
            let side = min(proxy.size.width, proxy.size.height) * scale
            Group {
                if let mark = style.mark {
                    Image(uiImage: mark)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Text(verbatim: style.initial)
                        .font(.system(size: side * 0.62, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .frame(width: proxy.size.width * scale, height: proxy.size.height * scale)
            .frame(width: proxy.size.width, height: proxy.size.height,
                   alignment: showsOwner ? .bottomLeading : .center)
            .overlay(alignment: .topTrailing) {
                if showsOwner {
                    let ownerSide = min(proxy.size.width, proxy.size.height) * Self.ownerScale
                    BoardOwnerSymbol(owner: style.owner)
                        .frame(width: ownerSide, height: ownerSide)
                }
            }
            .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

/// A circle for player one and a diamond for player two, so pieces differ by more
/// than color. Drawn in the current foreground style.
struct BoardOwnerSymbol: View {
    let owner: BoardPlayer

    var body: some View {
        Group {
            if owner == .one {
                Circle().fill(.foreground)
            } else {
                BoardOwnerDiamond().fill(.foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

private nonisolated struct BoardOwnerDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}
