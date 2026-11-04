import SwiftUI

nonisolated enum PiccanteVariety: CaseIterable, Equatable, Sendable {
    case heart, pinkStripes, nutFlower, goldDrizzle, whiteTruffle, rosette, praline, lavenderStripes, lavenderFlower

    @MainActor var artwork: ImageResource {
        switch self {
        case .heart: .gameHubPiccanteHeart
        case .pinkStripes: .gameHubPiccanteDrizzle
        case .nutFlower: .gameHubPiccanteNut
        case .goldDrizzle: .gameHubPiccanteGoldDrizzle
        case .whiteTruffle: .gameHubPiccanteWhiteTruffle
        case .rosette: .gameHubPiccanteRosette
        case .praline: .gameHubPiccantePraline
        case .lavenderStripes: .gameHubPiccanteLavenderStripes
        case .lavenderFlower: .gameHubPiccanteFlower
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .heart: .piccanteVarietyHeart
        case .pinkStripes: .piccanteVarietyPinkStripes
        case .nutFlower: .piccanteVarietyNutFlower
        case .goldDrizzle: .piccanteVarietyGoldDrizzle
        case .whiteTruffle: .piccanteVarietyWhiteTruffle
        case .rosette: .piccanteVarietyRosette
        case .praline: .piccanteVarietyPraline
        case .lavenderStripes: .piccanteVarietyLavenderStripes
        case .lavenderFlower: .piccanteVarietyLavenderFlower
        }
    }
}
