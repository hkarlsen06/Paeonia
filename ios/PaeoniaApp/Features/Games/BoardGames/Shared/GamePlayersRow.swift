import SwiftUI

/// Plain player portraits with names, turn emphasis and partner presence.
struct GamePlayersRow: View {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let partnerName: String
    let partnerIsHere: Bool

    var showsMarks = false

    @Environment(\.showsBoardOwnerSymbols) private var showsOwnerSymbols
    @ScaledMetric(relativeTo: .caption) private var ownerSymbolSide: CGFloat = 10
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        portrait(me, isMe: true)
                        Spacer(minLength: PaeoniaSpacing.space24)
                        portrait(partner, isMe: false)
                    }
                    stacked
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stacked: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            portrait(me, isMe: true)
            portrait(partner, isMe: false)
        }
    }

    private func portrait(_ player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        let active = turn.isActive(forMe: isMe)
        return VStack(spacing: PaeoniaSpacing.space8) {
            if showsMarks {
                BoardGamePlayerAvatar(player: player, isActive: false, isHere: !isMe && partnerIsHere, size: 48)
            } else {
                BoardGameAvatar(player: player, size: 48)
                    .gamePresenceRing(!isMe && partnerIsHere)
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
        }
        .padding(PaeoniaSpacing.space8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMe ? Text(.boardGamesPlayerYou) : partnerIsHere
            ? Text(.boardGamesStatusHere(partnerName)) : Text(verbatim: partnerName))
        .accessibilityValue(active ? turn.spoken(partnerName: partnerName).map { Text($0) } ?? Text("") : Text(""))
    }
}
