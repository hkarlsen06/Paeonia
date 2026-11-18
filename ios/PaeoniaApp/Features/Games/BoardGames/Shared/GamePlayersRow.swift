import SwiftUI

/// Plain player portraits with names, turn emphasis and partner presence. Once a
/// game ends, each name has the player's wins under it, or the couple's games sit
/// between the two.
struct GamePlayersRow: View {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let partnerName: String
    let partnerIsHere: Bool

    var showsMarks = false
    var result: BoardGameResultContent?

    @Environment(\.showsBoardOwnerSymbols) private var showsOwnerSymbols
    @ScaledMetric(relativeTo: .caption) private var ownerSymbolSide: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        portrait(me, isMe: true)
                        Spacer(minLength: PaeoniaSpacing.space24)
                        if let together {
                            together
                            Spacer(minLength: PaeoniaSpacing.space24)
                        }
                        portrait(partner, isMe: false)
                    }
                    stacked
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: turn)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: result == nil)
    }

    private var stacked: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            portrait(me, isMe: true)
            portrait(partner, isMe: false)
            together
        }
    }

    private var together: BoardGameTogetherCount? {
        guard let result, result.playStyle == .together else { return nil }
        return BoardGameTogetherCount(result: result, partnerName: partnerName)
    }

    private func portrait(_ player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        let active = turn.isActive(forMe: isMe)
        return VStack(spacing: PaeoniaSpacing.space8) {
            if showsMarks {
                BoardGamePlayerAvatar(player: player, isActive: active, size: 48)
            } else {
                BoardGameAvatar(player: player, size: 48)
                    .scaleEffect(active ? 1.1 : 1)
            }
            HStack(spacing: PaeoniaSpacing.space4) {
                if showsMarks && showsOwnerSymbols {
                    BoardOwnerSymbol(owner: player.style.owner)
                        .frame(width: ownerSymbolSide, height: ownerSymbolSide)
                }
                if isMe { Text(.boardGamesPlayerYou) } else { Text(verbatim: partnerName) }
            }
            .font(PaeoniaTypography.caption.weight(active ? .bold : .regular))
            .foregroundStyle(active ? Color.paeoniaTextPrimary : .paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            if let count = result?.winCount(isMe: isMe) {
                BoardGameResultCount(count: count)
                    .transition(.opacity)
            }
        }
        .padding(PaeoniaSpacing.space8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMe ? Text(.boardGamesPlayerYou) : partnerIsHere
            ? Text(.boardGamesStatusHere(partnerName)) : Text(verbatim: partnerName))
        .accessibilityValue(spokenValue(isMe: isMe, active: active))
    }

    /// "You won, 5 wins": the turn or the winner, and the wins once the game ends.
    private func spokenValue(isMe: Bool, active: Bool) -> Text {
        let turnLine = active ? turn.spoken(partnerName: partnerName).map { String(localized: $0) } : nil
        let wins = result?.winCount(isMe: isMe).map { String(localized: .boardGamesScoreWins($0.after)) }
        return Text(verbatim: [turnLine, wins].compactMap { $0 }.joined(separator: ", "))
    }
}
