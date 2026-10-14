import SwiftUI
import UIKit

/// One of the four corner colors of the Ludo board. A player picks one for
/// their pawns, and both phones show that player in it. The raw value is what
/// the server stores (`backend/convex/lib/ludo.ts`, `LUDO_COLORS`).
nonisolated enum LudoColor: String, Codable, CaseIterable, Sendable {
    case pink
    case lavender
    case gold
    case sky
}

extension LudoColor {
    var color: Color {
        switch self {
        case .pink: .boardGameMine
        case .lavender: .boardGamePartner
        case .gold: Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.goldCornerHex))
        case .sky: Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.skyCornerHex))
        }
    }

    var uiColor: UIColor {
        UIColor(color)
    }

    var name: LocalizedStringResource {
        switch self {
        case .pink: .ludoColorPink
        case .lavender: .ludoColorLavender
        case .gold: .ludoColorGold
        case .sky: .ludoColorSky
        }
    }
}

/// The two colors in play, as this phone sees them. The other two colors stay
/// on the board as the empty corners.
nonisolated struct LudoColorPair: Equatable, Sendable {
    let mine: LudoColor
    let partner: LudoColor

    /// Pink for me and lavender for my partner. The other board games always use these.
    static let standard = LudoColorPair(mine: .pink, partner: .lavender)

    /// The colors nobody plays, in the order of `LudoColor.allCases`. The first
    /// one fills the empty corner at the top left and the second the one at the
    /// bottom right.
    var unused: [LudoColor] {
        LudoColor.allCases.filter { $0 != mine && $0 != partner }
    }
}
