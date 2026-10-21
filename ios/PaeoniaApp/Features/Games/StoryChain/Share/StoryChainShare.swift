import SwiftUI

/// What the share sheet offers for a finished Story Chain story: a typeset card
/// and the plain words.
enum StoryChainShare {
    /// `content` is the story as the page draws it, so the card keeps the page's two
    /// inks, one for each writer and gold under a dared word.
    static func shareable(title: String, number: Int?, content: StoryChainPageContent) -> PaeoniaShareable {
        // A draft or a line that is still writing itself in is not part of the story.
        var content = content
        content.ghost = nil
        content.arrivingLineID = nil
        let finished = content
        return PaeoniaShareable(title: title, text: text(title: title, content: finished)) {
            PaeoniaShareRenderer.png(
                PaeoniaShareCardFrame {
                    StoryChainShareCard(title: title, number: number, content: finished)
                }
            )
        }
    }

    /// The title, the story as one paragraph, and a closing line.
    static func text(title: String, content: StoryChainPageContent) -> String {
        let story = ([content.opening].compactMap { $0 } + content.lines.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [title, story, String(localized: .shareStoryChainSignature)].joined(separator: "\n\n")
    }
}

/// The story on a card: the number, the title, the paragraph and a flower.
private struct StoryChainShareCard: View {
    let title: String
    let number: Int?
    let content: StoryChainPageContent

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            VStack(spacing: PaeoniaSpacing.space8) {
                if let number {
                    Text(.storyChainStoryNumber(number))
                        .font(PaeoniaTypography.caption.bold())
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(.paeoniaTextTertiary)
                }
                Text(verbatim: title)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
            }
            PaeoniaHeartDivider()
            StoryChainParagraph.text(for: content)
                .font(.system(size: 17, design: .serif))
                .lineSpacing(StoryChainPageStyle.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "camera.macro")
                .font(.system(size: 28))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
        .frame(width: PaeoniaShareRenderer.contentWidth)
    }
}
