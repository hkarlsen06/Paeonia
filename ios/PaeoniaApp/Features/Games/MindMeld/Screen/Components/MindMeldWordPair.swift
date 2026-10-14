import SwiftUI

/// The last two words as two chips with a small plus between, my word first. It
/// sits under the title of the write phase. When the chips do not fit side by side
/// (long words, large text), they stack.
struct MindMeldWordPair: View {
    let mine: String
    let theirs: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) {
                chip(mine, tint: .paeoniaPartnerOne, lines: 1)
                plus
                chip(theirs, tint: .paeoniaPartnerTwo, lines: 1)
            }
            VStack(spacing: PaeoniaSpacing.space8) {
                chip(mine, tint: .paeoniaPartnerOne, lines: 2)
                plus
                chip(theirs, tint: .paeoniaPartnerTwo, lines: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(PaeoniaTypography.caption.weight(.bold))
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityHidden(true)
    }

    private func chip(_ word: String, tint: Color, lines: Int) -> some View {
        MindMeldWordChip(word: word, tint: tint, font: PaeoniaTypography.bodyEmphasis, lines: lines)
    }
}

/// A word in capitals on a capsule with a thin border in one partner's color.
private struct MindMeldWordChip: View {
    let word: String
    let tint: Color
    let font: Font
    let lines: Int
    var hasMark = false

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            if hasMark {
                MindMeldPetalMark()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(tint)
            }
            Text(verbatim: word.localizedUppercase)
                .font(font)
                .tracking(0.5)
                .lineLimit(lines)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.paeoniaTextPrimary)
                // A chip that has to fit on one line keeps the width of its word.
                .fixedSize(horizontal: lines == 1, vertical: true)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(.paeoniaSurfaceSecondary, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.55), lineWidth: PaeoniaRadius.strokeDefault))
    }
}

// MARK: - Trail

/// The word pairs of earlier rounds, oldest first, with the gap between the two
/// words narrowing each round so the couple sees how they came closer.
struct MindMeldTrailView: View {
    // swiftlint:disable:next large_tuple
    typealias Pair = (mine: String, theirs: String, isMeld: Bool, isCounted: Bool)

    enum Style {
        /// Caption-size rows for the write phase. Every row is a plain pair.
        case compact
        /// Large rows for "Our melds". A meld ends in one merged chip, and a
        /// counted near miss ends in both words with "Counted".
        case detail
    }

    let pairs: [Pair]
    var style: Style = .compact

    private static let compactWidestGap: CGFloat = 28
    private static let compactNarrowestGap: CGFloat = 6
    private static let detailNarrowestInset: CGFloat = 72

    var body: some View {
        VStack(spacing: style == .compact ? PaeoniaSpacing.space4 : PaeoniaSpacing.space20) {
            ForEach(pairs.indices, id: \.self) { index in
                switch style {
                case .compact: compactRow(pairs[index], progress: progress(of: index))
                case .detail: detailRow(pairs[index], round: index + 1, progress: progress(of: index))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 0 for the first row and 1 for the last.
    private func progress(of index: Int) -> CGFloat {
        pairs.count > 1 ? CGFloat(index) / CGFloat(pairs.count - 1) : 0
    }

    // MARK: Compact

    private func compactRow(_ pair: Pair, progress: CGFloat) -> some View {
        let gap = Self.compactWidestGap + (Self.compactNarrowestGap - Self.compactWidestGap) * progress
        return HStack(spacing: gap) {
            Text(verbatim: pair.mine.localizedUppercase)
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .bold))
                .accessibilityHidden(true)
            Text(verbatim: pair.theirs.localizedUppercase)
        }
        .font(PaeoniaTypography.caption)
        .lineLimit(1)
        .foregroundStyle(.paeoniaTextTertiary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Detail

    @ViewBuilder
    private func detailRow(_ pair: Pair, round: Int, progress: CGFloat) -> some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(.mindMeldHistoryDetailRound(round))
                .font(PaeoniaTypography.caption.weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.paeoniaTextTertiary)
            if pair.isMeld && !pair.isCounted {
                mergedChip(pair.mine)
            } else {
                joinedChips(pair, inset: Self.detailNarrowestInset * progress)
            }
            if pair.isCounted {
                Text(.mindMeldHistoryDetailCounted)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaSuccess)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// My word, a thin line and the partner's word. A bigger `inset` pulls them
    /// toward the middle.
    private func joinedChips(_ pair: Pair, inset: CGFloat) -> some View {
        let mine: Color = pair.isMeld ? .paeoniaSuccess : .paeoniaPartnerOne
        let theirs: Color = pair.isMeld ? .paeoniaSuccess : .paeoniaPartnerTwo
        return HStack(spacing: 0) {
            MindMeldWordChip(word: pair.mine, tint: mine, font: PaeoniaTypography.sectionTitle, lines: 2)
                .layoutPriority(1)
            Capsule()
                .fill(LinearGradient(
                    colors: [mine.opacity(0.7), theirs.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: PaeoniaRadius.strokeEmphasis)
                .frame(minWidth: PaeoniaSpacing.space8)
                .accessibilityHidden(true)
            MindMeldWordChip(word: pair.theirs, tint: theirs, font: PaeoniaTypography.sectionTitle, lines: 2)
                .layoutPriority(1)
        }
        .padding(.horizontal, inset)
    }

    private func mergedChip(_ word: String) -> some View {
        MindMeldWordChip(
            word: word,
            tint: .paeoniaSuccess,
            font: PaeoniaTypography.sectionTitle,
            lines: 2,
            hasMark: true
        )
    }
}

#if DEBUG
#Preview("Pair") {
    VStack(spacing: PaeoniaSpacing.space24) {
        MindMeldWordPair(mine: "Ocean", theirs: "Sushi")
        MindMeldWordPair(mine: "Strawberry ice cream", theirs: "New York city")
        MindMeldWordPair(mine: "Ocean", theirs: "Sushi")
            .dynamicTypeSize(.accessibility3)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}

#Preview("Trail") {
    ScrollView {
        VStack(spacing: PaeoniaSpacing.space32) {
            MindMeldTrailView(pairs: [
                (mine: "Ocean", theirs: "Sushi", isMeld: false, isCounted: false),
                (mine: "Salt", theirs: "Rice", isMeld: false, isCounted: false),
                (mine: "Fish", theirs: "Soy", isMeld: false, isCounted: false),
            ])
            MindMeldTrailView(
                pairs: [
                    (mine: "Ocean", theirs: "Sushi", isMeld: false, isCounted: false),
                    (mine: "Salt", theirs: "Fish", isMeld: false, isCounted: false),
                    (mine: "Fish", theirs: "Fish", isMeld: true, isCounted: false),
                ],
                style: .detail
            )
            MindMeldTrailView(
                pairs: [
                    (mine: "Ocean", theirs: "Sushi", isMeld: false, isCounted: false),
                    (mine: "Wave", theirs: "Waves", isMeld: true, isCounted: true),
                ],
                style: .detail
            )
        }
        .padding()
    }
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
