import SwiftUI

extension GameKind {
    /// The color of the game's walls on the shared hub backdrop (`GameHubBackdrop`). Only the
    /// hue and saturation count, since the walls keep their own light and shade. Neighbors in
    /// the catalog differ, so the grid never shows two rooms of one color side by side.
    /// `art_asset.py text` checks each one: keep its list in step.
    var hubWallTint: Color {
        switch self {
        case .ludo: PaeoniaPalette.gold
        case .drawAndGuess: PaeoniaPalette.coralLight
        case .connectFour: PaeoniaPalette.blue
        case .mindMeld: PaeoniaPalette.lavender
        case .consensio: PaeoniaPalette.mint
        case .guessMySpot: PaeoniaPalette.teal
        case .dotsAndBoxes: PaeoniaPalette.orange
        case .ultimateTicTacToe: PaeoniaPalette.periwinkle
        case .piccante: PaeoniaPalette.orange
        case .storyChain: PaeoniaPalette.pink
        case .exquisiteCorpse: PaeoniaPalette.orchid
        }
    }
}
