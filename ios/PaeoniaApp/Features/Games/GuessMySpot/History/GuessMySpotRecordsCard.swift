import SwiftUI

/// The glass card over the top of "Our guesses": how many places, the score as the play
/// style shows it, and each partner's closest and average guess.
struct GuessMySpotRecordsCard: View {
    let records: RemoteGuessMySpotRecords
    let score: GuessMySpotScore?
    let places: Int
    let me: GamePlayer
    let partner: GamePlayer

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: "map.fill")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                if case let .together(total) = score {
                    Text(verbatim: GuessMySpotHistoryScreen.joined(
                        .guessMySpotHistoryPlaces(places),
                        .guessMySpotPointsTogether(total)
                    ))
                } else {
                    Text(.guessMySpotHistoryPlaces(places))
                }
            }
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)
            row(me, tint: .paeoniaPartnerOne, record: records.mine, points: ownPoints(isMe: true))
            row(partner, tint: .paeoniaPartnerTwo, record: records.partner, points: ownPoints(isMe: false))
        }
        .padding(PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.7)),
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space8)
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guessMySpot.history.records")
    }

    /// Each partner's own total, shown only when they play against each other.
    private func ownPoints(isMe: Bool) -> Int? {
        guard case let .against(mine, theirs) = score else { return nil }
        return isMe ? mine : theirs
    }

    private func row(
        _ player: GamePlayer,
        tint: Color,
        record: RemoteGuessMySpotGuesserRecord,
        points: Int?
    ) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaProfilePhotoAvatar(mediaAssetID: player.photoAssetID, name: player.name, tint: tint, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                if let points {
                    Text(.guessMySpotStatsPoints(points))
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .monospacedDigit()
                }
                Group {
                    if let closest = record.closestM, let average = record.averageM {
                        Text(verbatim: GuessMySpotHistoryScreen.joined(
                            .guessMySpotHistoryRecordsClosest(GuessMySpotText.distance(closest)),
                            .guessMySpotHistoryRecordsAverage(GuessMySpotText.distance(average))
                        ))
                    } else {
                        Text(.guessMySpotHistoryRecordsNone)
                    }
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(2)
            }
        }
    }
}

extension GuessMySpotHistoryScreen {
    /// Two localized parts on one line, joined by a middle dot.
    static func joined(_ first: LocalizedStringResource, _ second: LocalizedStringResource) -> String {
        "\(String(localized: first)) · \(String(localized: second))"
    }
}
