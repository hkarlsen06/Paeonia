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

    static func == (lhs: BoardPieceStyle, rhs: BoardPieceStyle) -> Bool {
        lhs.color == rhs.color && lhs.mark === rhs.mark && lhs.initial == rhs.initial
    }
}

/// Both players' styles, by board player.
struct BoardPieceStyles: Equatable {
    let one: BoardPieceStyle
    let two: BoardPieceStyle

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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
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
            .foregroundStyle(tint)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}
