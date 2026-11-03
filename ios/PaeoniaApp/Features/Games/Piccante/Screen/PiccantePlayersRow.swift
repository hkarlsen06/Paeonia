import SwiftUI

/// Piccante keeps the portraits plain, with presence on the partner's avatar.
struct PiccantePlayersRow: View {
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    let turn: BoardGameTurnLabel
    let partnerName: String
    let partnerIsHere: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                portrait(me, isMe: true)
                Spacer(minLength: PaeoniaSpacing.space24)
                portrait(partner, isMe: false)
            }
            VStack(spacing: PaeoniaSpacing.space16) {
                portrait(me, isMe: true)
                portrait(partner, isMe: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func portrait(_ player: BoardGamePlayerInfo, isMe: Bool) -> some View {
        let active = turn.isActive(forMe: isMe)
        return VStack(spacing: PaeoniaSpacing.space8) {
            BoardGameAvatar(player: player, size: 48)
                .gamePresenceRing(!isMe && partnerIsHere)
            Group {
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
