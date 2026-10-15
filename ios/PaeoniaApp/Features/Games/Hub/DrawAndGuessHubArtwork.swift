import SwiftUI

/// The Draw & Guess card's scene: a sheet of paper with a pink heart drawn on it and the
/// pencil that drew it. The beat pops in the letter tiles that spell what the drawing is,
/// in the card's language, to the right of the paper. It follows `docs/games/hub-artwork.md`.
struct DrawAndGuessHubArtwork: View {
    var body: some View {
        GameHubArtwork(duration: 1.4) { progress in
            DrawAndGuessHubScene(progress: progress)
        }
    }
}

/// In the canvas's pixels. The tiles pop in one by one, three to a row. Three tiles end
/// about 120 pixels from the right edge, so they keep clear of the card's corner.
private struct DrawAndGuessHubScene: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let paper = GameHubPlacement(base: CGPoint(x: 370, y: 630), width: 400, aspect: 1.033)
    private static let pencil = GameHubPlacement(base: CGPoint(x: 490, y: 640), width: 280, aspect: 1.673)
    private static let center = CGPoint(x: 764, y: 400)
    private static let tileSize: CGFloat = 84
    private static let tileSpacing: CGFloat = 10
    private static let tilesPerRow = 3
    private static let tileColors: [Color] = [
        .paeoniaAccentPrimary, .paeoniaInkGold, .paeoniaInkLavender, .paeoniaInkBlue, .paeoniaAccentSecondary,
    ]
    private static let tileTilts: [Double] = [-8, 5, -3, 7, -6, 4]

    var body: some View {
        let letters = Array(String(localized: .gamesHubArtworkWord))
        let rows = stride(from: 0, to: letters.count, by: Self.tilesPerRow).map { start in
            Array(start..<min(start + Self.tilesPerRow, letters.count))
        }
        ZStack {
            GameHubObject(image: .gameHubDrawAndGuessPaper, placement: Self.paper)
            GameHubObject(image: .gameHubDrawAndGuessPencil, placement: Self.pencil, shadow: false)
            VStack(spacing: Self.tileSpacing) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: Self.tileSpacing) {
                        ForEach(row, id: \.self) { index in
                            tile(letters[index], index: index, count: letters.count)
                        }
                    }
                }
            }
            .position(Self.center)
        }
    }

    /// A cream tile tinted in one of the ink colors, with the letter in dark plum, which
    /// reads at more than 4.5:1 on every tint.
    private func tile(_ letter: Character, index: Int, count: Int) -> some View {
        let start = 0.6 * Double(index) / Double(max(count - 1, 1))
        let pop = GameHubArtworkTiming.pop(progress, from: start, to: start + 0.3)
        return Image(.gameHubDrawAndGuessTile)
            .resizable()
            .accessibilityHidden(true)
            .colorMultiply(Self.tileColors[index % Self.tileColors.count])
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay {
                Text(String(letter))
                    .font(.system(size: Self.tileSize * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.paeoniaTextInverse)
            }
            .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 10, y: 7)
            .rotationEffect(.degrees(Self.tileTilts[index % Self.tileTilts.count]))
            .offset(y: index.isMultiple(of: 2) ? -5 : 5)
            .scaleEffect(max(0, pop))
            .opacity(min(1, max(0, pop) * 2))
    }
}

#if DEBUG
#Preview {
    DrawAndGuessHubArtwork()
        .frame(width: 335, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif
