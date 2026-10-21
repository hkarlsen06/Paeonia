import SwiftUI

/// The way into a memory's comments, under its photos: a card that shows the newest comment,
/// and the comments themselves as the shared chat, pushed on top of the memory. Either partner
/// can comment. A comment push opens the chat at once (`MemoriesViewModel.commentsRequestedMemoryID`).
struct MemoryCommentsSection: View {
    let record: MemoryRecord
    let viewModel: MemoriesViewModel

    @Environment(\.threadChatContext) private var context
    @State private var chat: ThreadChatViewModel?
    @State private var isShowingChat = false

    private var memoryID: UUID { record.snapshot.memoryID }
    private var subject: ThreadChatSubject { .memory(memoryID) }

    var body: some View {
        Group {
            if context.isAvailable {
                row
            }
        }
        .navigationDestination(isPresented: $isShowingChat) {
            if let chat {
                ThreadChatScreen(viewModel: chat)
                    .toolbar(.hidden, for: .tabBar)
                    .analyticsScreen("memory_comments")
            }
        }
        .onChange(of: viewModel.commentsRequestedMemoryID, initial: true) { _, requested in
            guard requested == memoryID, context.isAvailable else { return }
            viewModel.commentsRequestedMemoryID = nil
            open()
        }
    }

    private var row: some View {
        Button(action: open) {
            PaeoniaCard(padding: 0) { rowContent }
        }
        .buttonStyle(.paeoniaPressableRow)
        .accessibilityElement(children: .combine)
    }

    private var rowContent: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: PaeoniaSpacing.space24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.memoriesCommentsTitle)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                previewText
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if context.summaries?.isUnread(subject) ?? false {
                Circle()
                    .fill(.paeoniaAccentPrimary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var previewText: some View {
        if let line = previewLine {
            Text(verbatim: line)
        } else {
            Text(.memoriesCommentsRowEmpty)
        }
    }

    /// "Robin: Miss this day", for the newest comment.
    private var previewLine: String? {
        guard let summary = context.summaries?.summary(for: subject),
              let text = summary.lastMessagePreview
        else { return nil }
        let name = summary.lastMessageSenderUserID == context.participants.currentUserID
            ? String(localized: .memoriesCommentsRowYou)
            : context.participants.partnerName
        return String(localized: .memoriesCommentsRowPreview(name, text))
    }

    private func open() {
        guard !isShowingChat else { return }
        Task {
            // Read before the push, so the chat's first frame already has its comments.
            chat = await context.makeViewModel(subject: subject, header: ThreadChatHeader(memory: record))
            isShowingChat = chat != nil
        }
    }
}

extension ThreadChatHeader {
    /// The card at the top of a memory's comments: its photo, title and date.
    init(memory record: MemoryRecord) {
        let date = MemoryTimeline.parseLocalDate(record.snapshot.memoryDate) ?? record.snapshot.createdAt
        self.init(
            eyebrow: String(localized: .chatHeaderMemory),
            title: record.snapshot.title ?? "",
            detail: date.formatted(MemoryDateStyle.long),
            photoAssetID: record.snapshot.media.filter(\.isVisible).sortedForMemoryDisplay().first?.mediaAssetID
        )
    }
}
