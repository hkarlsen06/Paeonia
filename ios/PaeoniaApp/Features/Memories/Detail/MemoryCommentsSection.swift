import SwiftUI

/// The way into a memory's chat, under its photos: a card that shows the newest message, and
/// the chat itself, pushed on top of the memory. Either partner can write. The chat opens with
/// both partners' notes. A message push opens the chat at once
/// (`MemoriesViewModel.commentsRequestedMemoryID`).
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
            VStack(alignment: .leading, spacing: 0) {
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
        .padding(.vertical, PaeoniaSpacing.space8)
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

    /// "Robin: Miss this day", for the newest message.
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
            // Read before the push, so the chat's first frame already has its messages.
            chat = await context.makeViewModel(subject: subject, header: ThreadChatHeader(memory: record))
            isShowingChat = chat != nil
        }
    }
}

extension ThreadChatHeader {
    /// The card at the top of a memory's chat: its photo, title and date, then both partners'
    /// notes in the order the memory page shows them.
    init(memory record: MemoryRecord) {
        let snapshot = record.snapshot
        let date = MemoryTimeline.parseLocalDate(snapshot.memoryDate) ?? snapshot.createdAt
        let own = snapshot.ownNote?.visibleBody.map { ThreadChatNote(isOwn: true, body: $0) }
        let partner = snapshot.partnerNote?.visibleBody.map { ThreadChatNote(isOwn: false, body: $0) }
        self.init(
            eyebrow: String(localized: .chatHeaderMemory),
            title: snapshot.title ?? "",
            detail: date.formatted(MemoryDateStyle.long),
            photoAssetID: snapshot.media.filter(\.isVisible).sortedForMemoryDisplay().first?.mediaAssetID,
            notes: [own, partner].compactMap(\.self)
        )
    }
}
