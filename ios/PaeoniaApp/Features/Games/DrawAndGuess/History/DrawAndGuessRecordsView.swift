import SwiftUI

/// The "Records" section: first-try solves, the average solve time and the
/// fastest solve of both partners, side by side. It shows in both play styles.
struct DrawAndGuessRecordsView: View {
    let me: GamePlayer
    let partner: GamePlayer
    let mine: RemoteDrawAndGuessPlayerRecords?
    let theirs: RemoteDrawAndGuessPlayerRecords?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One number of the section, for one partner.
    private struct Value {
        /// The big line, or nil when the partner has nothing to show yet.
        var text: String?
        /// A smaller line under it, such as the word of the fastest solve.
        var detail: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Text(.gamesDrawAndGuessHistoryRecordsTitle)
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            if !showsNamesInValues {
                columns {
                    player(me, name: String(localized: .gamesDrawAndGuessRevealYou), isMe: true)
                    player(partner, name: partner.name, isMe: false)
                }
                .accessibilityHidden(true)
            }

            stat(
                .gamesDrawAndGuessHistoryRecordsFirstTry,
                mine: mine.map { Value(text: $0.firstTrySolves.formatted()) },
                theirs: theirs.map { Value(text: $0.firstTrySolves.formatted()) }
            )
            stat(
                .gamesDrawAndGuessHistoryRecordsAverage,
                mine: mine.map { Value(text: $0.averageSolveMs.map { DrawAndGuessHistoryFormat.duration(ms: $0) }) },
                theirs: theirs.map { Value(text: $0.averageSolveMs.map { DrawAndGuessHistoryFormat.duration(ms: $0) }) }
            )
            stat(
                .gamesDrawAndGuessHistoryRecordsFastest,
                mine: mine.map(fastest),
                theirs: theirs.map(fastest)
            )
        }
    }

    private func fastest(_ records: RemoteDrawAndGuessPlayerRecords) -> Value {
        guard let ms = records.fastestSolveMs else { return Value() }
        return Value(
            text: DrawAndGuessHistoryFormat.duration(ms: ms),
            detail: records.fastestSolveWord.map(DrawAndGuessAnswer.display)
        )
    }

    // MARK: - Layout

    /// At accessibility text sizes the two columns stack, and each value carries
    /// the name of its partner.
    private var showsNamesInValues: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func columns(@ViewBuilder _ content: () -> some View) -> some View {
        let layout = showsNamesInValues
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space16))
        return layout { content() }
    }

    private func player(_ player: GamePlayer, name: String, isMe: Bool) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            GameAvatar(player: player, isMe: isMe, size: 28)
            Text(name)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: LocalizedStringResource, mine: Value?, theirs: Value?) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            Text(label)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            columns {
                valueCell(mine, name: String(localized: .gamesDrawAndGuessRevealYou))
                valueCell(theirs, name: partner.name)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken(mine: mine, theirs: theirs)))
    }

    private func valueCell(_ value: Value?, name: String) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            if showsNamesInValues {
                Text(name)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            if let text = value?.text {
                Text(text)
                    .font(PaeoniaTypography.title)
                    .monospacedDigit()
                    .foregroundStyle(.paeoniaTextPrimary)
            } else {
                Text(.gamesDrawAndGuessHistoryRecordsNone)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextTertiary)
            }
            if let detail = value?.detail {
                Text(detail)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spoken(mine: Value?, theirs: Value?) -> String {
        [
            (String(localized: .gamesDrawAndGuessRevealYou), mine),
            (partner.name, theirs),
        ].map { name, value in
            String(localized: .gamesDrawAndGuessHistoryRecordsSpoken(name, spoken(value)))
        }.joined(separator: ". ")
    }

    private func spoken(_ value: Value?) -> String {
        guard let text = value?.text else { return String(localized: .gamesDrawAndGuessHistoryRecordsNone) }
        guard let detail = value?.detail else { return text }
        return String(localized: .gamesDrawAndGuessHistoryRecordsFastestSpoken(text, detail))
    }
}
