import SwiftUI

/// The top of the hub: the days in a row both partners played a game, and the days they
/// played together in all. The hub shows it once they have played together. A streak
/// under 2 days stays out, since "1 day in a row" says nothing.
struct GamesHubPlayDays: View {
    let playDays: RemoteGamePlayDays

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space8) { facts }
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) { facts }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("games.hub.playDays")
    }

    @ViewBuilder private var facts: some View {
        if playDays.streak >= 2 {
            fact(.gamesHubPlayDaysStreak(playDays.streak), systemImage: "flame.fill", tint: .paeoniaAccentSecondary)
        }
        fact(.gamesHubPlayDaysTotal(playDays.total), systemImage: "heart.fill", tint: .paeoniaInkLavender)
    }

    private func fact(_ text: LocalizedStringResource, systemImage: String, tint: Color) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.paeoniaTextPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4 + PaeoniaSpacing.space2)
        .background(.paeoniaSurfacePrimary, in: Capsule())
    }
}
