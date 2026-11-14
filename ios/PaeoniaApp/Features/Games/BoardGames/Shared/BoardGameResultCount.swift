import SwiftUI

/// A number under the players once a game ends: a player's wins, or the couple's
/// games. A number that went up counts up a moment after the result panel rises,
/// with "+1" at its top trailing corner and a tap of the phone. Reduce Motion
/// shows the final number at once and keeps the tap.
struct BoardGameResultCount: View {
    let count: BoardGameCount

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCounting = false

    /// The result panel rises first.
    private static let delay: TimeInterval = 0.45

    private var showsCount: Bool { isCounting || reduceMotion }

    var body: some View {
        DrawAndGuessCountingNumber(from: count.before, to: count.after, isCounting: showsCount, animates: !reduceMotion)
            .font(PaeoniaTypography.title)
            .foregroundStyle(.paeoniaTextPrimary)
            .overlay(alignment: .topTrailing) {
                // The guide sits outside the `if`. Inside it, SwiftUI ignores the guide
                // and puts "+1" on top of the number.
                Group {
                    if count.added > 0 {
                        DrawAndGuessAddedPoints(points: count.added, isShown: showsCount, animates: !reduceMotion)
                            .font(PaeoniaTypography.caption.weight(.semibold))
                            .fixedSize()
                    }
                }
                .alignmentGuide(.trailing) { $0[.leading] - PaeoniaSpacing.space2 }
            }
            .task { await countUp() }
    }

    private func countUp() async {
        if !reduceMotion {
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled else { return }
            isCounting = true
        }
        if count.added > 0 {
            PaeoniaHaptics.streakTick(intensity: 0.6)
        }
    }
}

/// The couple's finished games between the two players, when they play together.
struct BoardGameTogetherCount: View {
    let result: BoardGameResultContent
    let partnerName: String

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space2) {
            Image(systemName: "heart.fill")
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaAccentPrimary)
            BoardGameResultCount(count: result.gamesCount)
            Text(result.gamesFinished == 1 ? .boardGamesResultGameTogether : .boardGamesResultGamesTogether)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(result.score.spoken(partnerName: partnerName)))
        .accessibilityIdentifier("boardGames.result.score")
    }
}

extension BoardGameResultContent {
    /// A player's wins after this game, when the couple plays against each other.
    func winCount(isMe: Bool) -> BoardGameCount? {
        guard playStyle == .against else { return nil }
        return isMe ? myCount : partnerCount
    }
}
