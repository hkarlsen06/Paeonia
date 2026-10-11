import ExyteChat
import SwiftUI

struct DailyQuestionChatView: View {
    @State private var viewModel: DailyQuestionChatViewModel
    let participants: DailyChallengeParticipants
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var showsSendingReassurance = false

    init(
        viewModel: DailyQuestionChatViewModel,
        participants: DailyChallengeParticipants
    ) {
        _viewModel = State(initialValue: viewModel)
        self.participants = participants
    }

    var body: some View {
        ChatView(
            messages: exyteMessages,
            chatType: .conversation,
            didSendMessage: { draft async -> Bool in
                // Tapping a failed message's red icon sends its draft back with the id
                // of the message that failed, so the retry replaces it.
                await viewModel.send(draft.text, replacingFailed: draft.id.flatMap(UUID.init(uuidString:)))
            }
        )
        .mainHeaderBuilder { questionContext }
        .betweenListAndInputViewBuilder { sendingReassurance }
        .localization(chatLocalization)
        .setAvailableInputs([.text])
        .showMessageMenuOnLongPress(false)
        .keyboardDismissMode(.interactive)
        .chatTheme(chatTheme)
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(.dailyChatNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.question.id) {
            await viewModel.load()
            await viewModel.observeLiveUpdates()
        }
        .task(id: viewModel.hasSendingMessages) {
            // A send that finishes quickly never shows the strip, so the list does not jump.
            showsSendingReassurance = false
            guard viewModel.hasSendingMessages else { return }
            try? await Task.sleep(for: .seconds(2))
            showsSendingReassurance = !Task.isCancelled
        }
        .onChange(of: participants) { _, participants in
            viewModel.refreshParticipants(participants)
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }

    private var exyteMessages: [ExyteChat.Message] {
        viewModel.messages.map { message in
            let isCurrentUser = message.senderUserID == viewModel.participants.currentUserID
            let name = isCurrentUser
                ? String(localized: .dailyChallengeChoiceYou)
                : viewModel.participants.partnerName
            return ExyteChat.Message(
                // A message keeps its row when the server confirms it.
                id: (message.clientOperationID ?? message.id).uuidString,
                user: ExyteChat.User(
                    id: message.senderUserID.uuidString,
                    name: name,
                    avatarURL: nil,
                    isCurrentUser: isCurrentUser
                ),
                status: messageStatus(message),
                createdAt: message.createdAt,
                text: message.body
            )
        }
    }

    private func messageStatus(_ message: DailyQuestionChatMessage) -> ExyteChat.Message.Status {
        if message.sendFailed {
            return .error(
                DraftMessage(
                    id: message.clientOperationID?.uuidString,
                    text: message.body,
                    medias: [],
                    giphyMedia: nil,
                    recording: nil,
                    replyMessage: nil,
                    createdAt: message.createdAt
                )
            )
        }
        return message.isSending ? .sending : .sent
    }

    private var questionContext: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(viewModel.question.prompt)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            DailyAnswerDetailsView(
                question: viewModel.question,
                participants: viewModel.participants
            )

            if viewModel.messages.isEmpty, !viewModel.isLoading {
                Label {
                    Text(.dailyChatEmptyMessage)
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .accessibilityHidden(true)
                }
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .padding(.top, PaeoniaSpacing.space4)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sendingReassurance: some View {
        if viewModel.hasSendingMessages, showsSendingReassurance {
            Text(.dailyChatSendingReassurance)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.paeoniaBackgroundPrimary)
        }
    }

    private var chatLocalization: ChatLocalization {
        ChatLocalization(
            inputPlaceholder: String(localized: .dailyChatComposerPlaceholder),
            signatureText: String(localized: .dailyChatComposerSignature),
            cancelButtonText: String(localized: .dailyChatComposerCancel),
            recentToggleText: String(localized: .dailyChatComposerRecent),
            waitingForNetwork: String(localized: .dailyChatComposerOffline),
            recordingText: String(localized: .dailyChatComposerRecording),
            replyToText: String(localized: .dailyChatComposerReply)
        )
    }

    private var chatTheme: ChatTheme {
        ChatTheme(
            colors: .init(
                mainBG: .paeoniaBackgroundPrimary,
                mainTint: .paeoniaAccentPrimary,
                mainText: .paeoniaTextPrimary,
                mainCaptionText: .paeoniaTextSecondary,
                messageMyBG: .paeoniaAccentSecondary,
                messageReadStatus: .paeoniaAccentPrimary,
                messageMyText: .paeoniaTextPrimary,
                messageMyTimeText: .paeoniaTextPrimary.opacity(0.72),
                messageFriendBG: .paeoniaSurfacePrimary,
                messageFriendText: .paeoniaTextPrimary,
                messageFriendTimeText: .paeoniaTextTertiary,
                messageSystemBG: .paeoniaSurfaceSecondary,
                messageSystemText: .paeoniaTextPrimary,
                messageSystemTimeText: .paeoniaTextTertiary,
                inputBG: .paeoniaBackgroundSecondary,
                inputText: .paeoniaTextPrimary,
                inputPlaceholderText: .paeoniaTextTertiary,
                inputSignatureBG: .paeoniaBackgroundSecondary,
                inputSignatureText: .paeoniaTextPrimary,
                inputSignaturePlaceholderText: .paeoniaTextTertiary,
                menuBG: .paeoniaSurfacePrimary,
                menuText: .paeoniaTextPrimary,
                menuTextDelete: .paeoniaError,
                statusError: .paeoniaError,
                statusGray: .paeoniaTextTertiary,
                sendButtonBackground: .paeoniaAccentPrimary,
                recordDot: .paeoniaError
            )
        )
    }

    private func showBanner(for notice: DailyQuestionChatViewModel.Notice?) {
        guard let notice else { return }
        bannerCenter.show(
            .error(
                title: String(localized: notice.title),
                message: String(localized: notice.message)
            )
        )
        viewModel.dismissNotice()
    }
}
