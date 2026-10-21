import SwiftUI

/// Replying to a story and reading the replies. Both go through the story's chat
/// (`StoryReplies`), the same chat view and send queue as a memory's comments.
extension StoryViewer {
    func replyBar(for story: Story) -> some View {
        StoryReplyBar(
            partnerName: people.partnerName,
            replies: replies,
            isFocused: $isReplyFocused,
            hasConversation: hasConversation(for: story),
            hasUnreadReply: hasUnreadReply(for: story),
            onSend: { Task { await sendReply() } },
            onOpenReplies: openReplies
        )
        .animation(PaeoniaMotion.stateChange, value: replies.justSent)
    }

    /// Someone has written in this story's chat.
    func hasConversation(for story: Story) -> Bool {
        chatContext.summaries?.summary(for: .story(story.id)) != nil
    }

    func hasUnreadReply(for story: Story) -> Bool {
        chatContext.summaries?.isUnread(.story(story.id)) ?? false
    }

    /// The card at the top of the replies, so the conversation shows which story it is about.
    private func header(for story: Story) -> ThreadChatHeader {
        ThreadChatHeader(
            eyebrow: people.isOwn(story)
                ? String(localized: .chatHeaderYourStory)
                : String(localized: .chatHeaderStory(people.partnerName)),
            title: story.caption ?? "",
            detail: story.createdAt.formatted(date: .abbreviated, time: .shortened),
            photoAssetID: story.mediaAssetID
        )
    }

    /// Opens the chat of the story on screen. The first story of a push about a reply opens
    /// its replies too.
    func loadReplies(for story: Story) async {
        await replies.load(for: story, header: header(for: story), context: chatContext)
        if content.showsReplies, !didOpenRequestedReplies, replies.chat != nil {
            didOpenRequestedReplies = true
            isShowingReplies = true
        }
    }

    func sendReply() async {
        if await replies.send() {
            isReplyFocused = false
            PaeoniaHaptics.selection()
        } else if let notice = replies.chat?.notice {
            bannerCenter.show(
                .error(title: String(localized: notice.title), message: String(localized: notice.message))
            )
            replies.chat?.dismissNotice()
        }
    }

    func openReplies() {
        guard replies.chat != nil else { return }
        isReplyFocused = false
        isShowingReplies = true
    }

    @ViewBuilder
    var repliesSheet: some View {
        if let chat = replies.chat {
            ThreadChatScreen(viewModel: chat, embedsNavigationStack: true) {
                isShowingReplies = false
            }
            .analyticsScreen("story_replies")
        }
    }
}
