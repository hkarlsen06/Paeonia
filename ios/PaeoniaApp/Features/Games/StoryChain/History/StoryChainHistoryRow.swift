import SwiftUI

/// One finished story in "Our stories": the title in serif, the first line, and
/// when it finished and how long it is. A filled star shows when this person
/// starred it.
struct StoryChainHistoryRow: View {
    let item: RemoteStoryChainHistoryItem
    let isStarred: Bool

    private static let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
    private static let titleFont = Font.system(.title3, design: .serif, weight: .semibold)

    var body: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(verbatim: item.title)
                    .font(Self.titleFont)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: item.firstLine)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: caption)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityLabel(Text(.favoritesStarred))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: Self.shape)
        .contentShape(Self.shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storyChain.history.row")
    }

    /// "Oct 13 · 14 lines".
    private var caption: String {
        let date = item.finishedAt.formatted(.dateTime.month(.abbreviated).day())
        let lines = String(localized: .storyChainHistoryRowLines(item.lineCount))
        return "\(date) \u{00B7} \(lines)"
    }
}
