import SwiftUI

/// The points of a solved round, for the guesser and for the drawer. "Together"
/// shows the couple's total counting up. "Against each other" shows one column
/// for each partner, with no winner banner.
struct DrawAndGuessScorePanel: View {
    let score: DrawAndGuessRevealScore
    let me: GamePlayer
    let partner: GamePlayer
    let isCounting: Bool
    let animates: Bool
    let showsSpeedBonus: Bool
    let showsFirstTryBonus: Bool
    /// The result failed to send at least once. Only then does the panel say the
    /// score updates later, so a result on its normal way never flashes that line.
    let isHeldOnPhone: Bool

    /// The server confirmed a result that was only on this phone, with a bonus
    /// the reveal did not plan for. The line shows without a second celebration.
    @State private var bonusArrivedLate = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            switch score.style {
            case let .together(column):
                together(column)
            case let .against(mine, theirs):
                against(mine: mine, theirs: theirs)
            }
            if score.isEstimate, isHeldOnPhone {
                Text(.gamesDrawAndGuessRevealOfflineScore)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaSyncPending)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: score) { _, _ in
            if isCounting { bonusArrivedLate = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenSummary))
        .accessibilityIdentifier("draw.reveal.score")
    }

    // MARK: Together

    private func together(_ column: DrawAndGuessRevealScore.Column) -> some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            HStack(spacing: PaeoniaSpacing.space12) {
                GameAvatar(player: me, isMe: true, size: 44)
                PaeoniaHeartDivider(width: 72)
                GameAvatar(player: partner, isMe: false, size: 44)
            }
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                DrawAndGuessCountingNumber(
                    from: column.before,
                    to: column.after,
                    isCounting: isCounting,
                    animates: animates
                )
                .font(PaeoniaTypography.countdownNumber)
                .foregroundStyle(.paeoniaTextPrimary)
                DrawAndGuessAddedPoints(points: column.added, isShown: isCounting, animates: animates)
                    .font(PaeoniaTypography.title)
            }
            Text(.gamesDrawAndGuessRevealPointsTogether)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }

    // MARK: Against each other

    @ViewBuilder
    private func against(mine: DrawAndGuessRevealScore.Column, theirs: DrawAndGuessRevealScore.Column) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space24))
        layout {
            column(player: me, isMe: true, name: Text(.gamesDrawAndGuessRevealYou), data: mine)
            column(player: partner, isMe: false, name: Text(partner.name), data: theirs)
        }
    }

    private func column(
        player: GamePlayer,
        isMe: Bool,
        name: Text,
        data: DrawAndGuessRevealScore.Column
    ) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            GameAvatar(player: player, isMe: isMe, size: 44)
            name
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space4) {
                DrawAndGuessCountingNumber(
                    from: data.before,
                    to: data.after,
                    isCounting: isCounting,
                    animates: animates
                )
                .font(PaeoniaTypography.countdownNumber)
                .foregroundStyle(.paeoniaTextPrimary)
                DrawAndGuessAddedPoints(points: data.added, isShown: isCounting, animates: animates)
                    .font(PaeoniaTypography.bodyEmphasis)
            }
            VStack(spacing: PaeoniaSpacing.space2) {
                ForEach(Array(data.lines.enumerated()), id: \.offset) { _, line in
                    lineText(line)
                }
            }
            .font(PaeoniaTypography.caption)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func lineText(_ line: DrawAndGuessRevealScore.Line) -> some View {
        switch line.kind {
        case .word:
            Text(.gamesDrawAndGuessRevealLineWord(line.points))
                .foregroundStyle(.paeoniaTextSecondary)
        case .drawing:
            Text(.gamesDrawAndGuessRevealLineDrawing(line.points))
                .foregroundStyle(.paeoniaTextSecondary)
        case .speedBonus:
            Text(.gamesDrawAndGuessRevealLineSpeed(line.points))
                .foregroundStyle(Color.paeoniaInkGold)
                .opacity(showsSpeedBonus || bonusArrivedLate ? 1 : 0)
                .scaleEffect(showsSpeedBonus || bonusArrivedLate || !animates ? 1 : 0.8)
        case .firstTry:
            Text(.gamesDrawAndGuessRevealLineFirstTry(line.points))
                .foregroundStyle(.paeoniaTextSecondary)
                .opacity(showsFirstTryBonus || bonusArrivedLate ? 1 : 0)
                .scaleEffect(showsFirstTryBonus || bonusArrivedLate || !animates ? 1 : 0.8)
        }
    }

    private var spokenSummary: LocalizedStringResource {
        switch score.style {
        case let .together(column):
            .gamesDrawAndGuessScoreTogetherA11Y(String(localized: .gamesDrawAndGuessPoints(column.after)))
        case let .against(mine, theirs):
            .gamesDrawAndGuessScoreAgainstA11Y(
                String(localized: .gamesDrawAndGuessPoints(mine.after)),
                partner.name,
                String(localized: .gamesDrawAndGuessPoints(theirs.after))
            )
        }
    }
}

/// A total that counts from the old number to the new one.
struct DrawAndGuessCountingNumber: View {
    let from: Int
    let to: Int
    let isCounting: Bool
    let animates: Bool
    @State private var shown: Int

    init(from: Int, to: Int, isCounting: Bool, animates: Bool) {
        self.from = from
        self.to = to
        self.isCounting = isCounting
        self.animates = animates
        _shown = State(initialValue: isCounting && !animates ? to : from)
    }

    var body: some View {
        Text(verbatim: "\(shown)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onChange(of: isCounting, initial: true) { _, counting in
                guard counting else { return }
                if animates {
                    withAnimation(.linear(duration: 0.6)) { shown = to }
                } else {
                    shown = to
                }
            }
            // The server's total replaces the one this phone guessed, without counting again.
            .onChange(of: to) { _, newTotal in
                if isCounting { shown = newTotal }
            }
    }
}

/// "+3" next to a total. It pops in when the count starts.
struct DrawAndGuessAddedPoints: View {
    let points: Int
    let isShown: Bool
    let animates: Bool

    var body: some View {
        Text(verbatim: "+\(points)")
            .monospacedDigit()
            .foregroundStyle(.paeoniaAccentPrimary)
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown || !animates ? 1 : 0.5, anchor: .leading)
            .animation(animates ? PaeoniaMotion.cardReveal : nil, value: isShown)
    }
}
