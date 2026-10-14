import SwiftUI

/// The story page: an eyebrow, the title on a finished story, the byline, the
/// paragraph, and a slot below it for the composer or the status.
///
/// The screen puts this inside its own scroll view. The column is at most 560
/// points wide and centered, so a story reads like a book page on iPad too.
/// A tap on a line opens a popover with `lineInfo` for the tapped line.
struct StoryChainPageView<LineInfo: View, Trailing: View>: View {
    let content: StoryChainPageContent
    /// The small line above the story, such as "Story 4".
    let eyebrow: Text
    /// The name of a finished story.
    var title: String?
    /// How much of the title has written itself in, from 0 to 1.
    var titleProgress: Double = 1
    /// The line under the title, such as "by you and Robin".
    var byline: Text?
    var isBylineShown = true
    let youLabel: String
    let openingLabel: String
    var onArrivalFinished: (UUID) -> Void = { _ in }
    @ViewBuilder var lineInfo: (StoryChainPageLine) -> LineInfo
    @ViewBuilder var trailing: () -> Trailing

    @State private var selection: LineSelection?

    private struct LineSelection: Identifiable, Equatable {
        let id: UUID
        let rect: CGRect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            header
            StoryChainPageText(
                content: content,
                youLabel: youLabel,
                openingLabel: openingLabel,
                onTapLine: { id, rect in
                    selection = LineSelection(id: id, rect: rect)
                },
                onArrivalFinished: onArrivalFinished
            )
            .popover(
                item: $selection,
                attachmentAnchor: .rect(.rect(selection?.rect ?? .zero))
            ) { selection in
                if let line = content.lines.first(where: { $0.id == selection.id }) {
                    lineInfo(line)
                        .presentationCompactAdaptation(.popover)
                }
            }
            trailing()
        }
        .paeoniaReadableWidth(StoryChainPageStyle.measure)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            eyebrow
                .font(PaeoniaTypography.caption.bold())
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.paeoniaTextTertiary)
                .frame(maxWidth: .infinity, alignment: title == nil ? .leading : .center)
                .accessibilityAddTraits(.isHeader)
            if let title {
                StoryChainTitleText(title: title, progress: titleProgress)
                if let byline {
                    byline
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .opacity(isBylineShown ? 1 : 0)
                        .offset(y: isBylineShown ? 0 : PaeoniaSpacing.space8)
                }
            }
        }
    }
}

#if DEBUG
private enum StoryChainPagePreviewData {
    static let content = StoryChainPageContent(
        opening: "A key arrived in the post with no address on it.",
        lines: [
            StoryChainPageLine(
                id: UUID(), number: 1, text: "It opened nothing in town, so she took the night bus to the coast.",
                isMine: true, usedDare: nil, authorName: "Sam", createdAt: .now
            ),
            StoryChainPageLine(
                id: UUID(), number: 2, text: "At the last stop a lighthouse was waiting, though nobody built it.",
                isMine: false, usedDare: "lighthouse", authorName: "Robin", createdAt: .now
            ),
        ],
        ghost: StoryChainGhost(text: "Sam knocked on the", isLast: false)
    )
}

#Preview("Writing") {
    ScrollView {
        StoryChainPageView(
            content: StoryChainPagePreviewData.content,
            eyebrow: Text(verbatim: "Story 4"),
            title: "The lighthouse that moved",
            byline: Text(verbatim: "by you and Robin"),
            youLabel: "You",
            openingLabel: "Opening",
            lineInfo: { line in
                StoryChainLineInfoView(name: line.authorName, time: "Tue 21:04") {
                    Circle().fill(.paeoniaPartnerTwo).frame(width: 32, height: 32)
                }
            },
            trailing: { StoryChainTypingDots(ink: .paeoniaAccentPrimary) }
        )
    }
    .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
}
#endif
