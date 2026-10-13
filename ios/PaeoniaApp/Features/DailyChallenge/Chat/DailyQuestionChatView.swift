import ExyteChat
import SwiftUI

/// A question's own page, laid out like a group chat. Paeonia sends the question,
/// then both answers follow as bubbles from the people who wrote them, then the
/// conversation about them. Until both answers are revealed the page shows what is
/// there and says who it is waiting for, with no composer.
///
/// The chat follows Tidex's friends chat: the same ExyteChat setup, row gestures
/// (swipe to reply, swipe left for times, swipe right to go back), long-press menu,
/// and a composer of its own. The rows come from a cached `DailyChatProjection`, and
/// ExyteChat redraws only rows whose content changed, so scrolling stays smooth.
struct DailyQuestionChatView: View {
    private static let bottomComposerClearance: CGFloat = 14
    private static let highlightDuration: Duration = .seconds(1.6)

    @State private var viewModel: DailyQuestionChatViewModel
    let question: DailyChallengeQuestion
    let participants: DailyChallengeParticipants
    var onReport: ((PrivacyReportTarget) -> Void)?
    /// The user's answer while it is still sending, shown on the waiting page until
    /// this phone has it.
    var sendingAnswer: DailySendingPreview?
    /// Set when the page opens right after answering. The partner's answer lights up
    /// with a haptic when it shows, once.
    var revealsPartnerAnswer = false
    /// Swiping right calls this instead of `dismiss`, for a page that owns its cover.
    var onClose: (() -> Void)?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoViewer: PaeoniaImageViewerSelection?
    @State private var projectionStore = DailyChatProjectionStore()
    @State private var timestampRevealOffset: CGFloat = 0
    @State private var highlightedRowID: String?
    /// Where the list scrolls next. Nil keeps the list where it is.
    @State private var scrollTarget: ScrollToParams?
    @State private var didApplyOpeningScroll = false
    @State private var didRevealPartnerAnswer = false

    init(
        viewModel: DailyQuestionChatViewModel,
        question: DailyChallengeQuestion,
        participants: DailyChallengeParticipants,
        onReport: ((PrivacyReportTarget) -> Void)? = nil,
        sendingAnswer: DailySendingPreview? = nil,
        revealsPartnerAnswer: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.question = question
        self.participants = participants
        self.onReport = onReport
        self.sendingAnswer = sendingAnswer
        self.revealsPartnerAnswer = revealsPartnerAnswer
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if viewModel.isChatAvailable {
                chat
            } else {
                waitingPage
            }
        }
        .paeoniaReadableWidth()
        .paeoniaScreenBackground()
        .navigationTitle(Text(.dailyChatNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.isChatAvailable) {
            guard viewModel.isChatAvailable else { return }
            await viewModel.load()
            await viewModel.observeLiveUpdates()
        }
        .onChange(of: participants) { _, participants in
            viewModel.refreshParticipants(participants)
        }
        .onChange(of: question) { _, question in
            viewModel.refreshQuestion(question)
        }
        .task(id: viewModel.isChatAvailable) {
            guard viewModel.isChatAvailable else { return }
            await viewModel.presence.observe()
        }
        .onAppear { viewModel.setScreenActive(scenePhase == .active) }
        .onDisappear { viewModel.setScreenActive(false) }
        .onChange(of: scenePhase) { _, phase in viewModel.setScreenActive(phase == .active) }
        .onChange(of: viewModel.presence.partnerIsTyping) { _, isTyping in
            guard isTyping else { return }
            AccessibilityNotification.Announcement(
                String(localized: .dailyChatTyping(viewModel.participants.partnerName))
            ).post()
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
        .onChange(of: viewModel.hasReadStore) { applyOpeningScroll() }
        .onChange(of: revealedPartnerAnswerRowID, initial: true) { revealPartnerAnswer() }
        .paeoniaImageViewer(selection: $photoViewer)
    }

    private var projectionInput: DailyChatProjection.Input {
        DailyChatProjection.Input(
            prompt: viewModel.question.prompt,
            questionStartsAt: viewModel.question.startsAt,
            answers: viewModel.answers,
            messages: viewModel.messages,
            currentUserID: viewModel.participants.currentUserID,
            partnerName: viewModel.participants.partnerName,
            youName: String(localized: .dailyChallengeChoiceYou),
            partnerIsTyping: viewModel.presence.partnerIsTyping,
            partnerLastReadMessageID: viewModel.presence.partnerLastReadMessageID,
            ownAnswerSeenByPartner: viewModel.question.ownAnswerSeenByPartnerAt != nil
        )
    }

    private var projection: DailyChatProjection {
        projectionStore.projection(for: projectionInput)
    }

    // MARK: - Chat

    private var chat: some View {
        let projection = projection
        return ChatView(
            messages: projection.highlighting(highlightedRowID),
            chatType: .conversation,
            replyMode: .quote,
            // The composer sends by itself.
            didSendMessage: { _ in },
            messageBuilder: { params in
                if let row = projection.rowsByID[params.message.id] {
                    messageRow(row, messageFrame: params.messageFrame)
                }
            },
            inputViewBuilder: { params in
                DailyChatComposer(
                    text: params.text,
                    replyPreview: replyPreview,
                    focusRequest: viewModel.composerFocusRequest,
                    onCancelReply: viewModel.cancelReply,
                    onSendText: { await viewModel.send($0) },
                    onSendPhotos: { await viewModel.send($0, photos: $1) },
                    onSendVoice: { await viewModel.sendVoice(fileURL: $0, durationMs: $1) },
                    onTextChanged: viewModel.draftChanged
                )
            },
            messageMenuAction: handleMenuAction
        )
        .localization(chatLocalization)
        .showDateHeaders(true)
        .dateHeaderBuilder { DailyChatDateSeparator(date: $0) }
        .appliesFocusModifierToCustomInputView(false)
        .animateMessageUpdates(false)
        .betweenListAndInputViewBuilder { footerAccessory }
        .showMessageTimeView(false)
        .showMessageMenuOnLongPress(true)
        .showScrollToBottomButton(false)
        .setAvailableInputs([.text])
        .keyboardDismissMode(.interactive)
        .contentInsets(bottom: Self.bottomComposerClearance)
        .scrollTo(scrollTarget)
        .chatTheme(chatTheme)
        .overlay {
            ZStack {
                DailyChatNavigationGestureBridge { close() }
                DailyChatTimestampRevealGestureBridge(
                    isEnabled: true,
                    onChanged: handleBackgroundTimestampRevealChanged,
                    onEnded: handleBackgroundTimestampRevealEnded
                )
            }
            .allowsHitTesting(false)
        }
        .onAppear { applyOpeningScroll() }
    }

    private func messageRow(_ row: DailyChatRow, messageFrame: Binding<CGRect>?) -> some View {
        DailyChatMessageRow(
            row: row,
            participants: viewModel.participants,
            mediaKind: viewModel.question.mediaAnswerKind,
            isHighlighted: row.id == highlightedRowID,
            onReply: row.message.flatMap { message in
                viewModel.canReply(to: message) ? { viewModel.setReplyTarget(message) } : nil
            },
            onRetry: { retry(row.message) },
            onTapQuoted: jumpToMessage,
            onOpenPhoto: openPhoto,
            timestampRevealOffset: $timestampRevealOffset,
            messageFrame: messageFrame
        )
        .id(row.id)
    }

    /// Floats above the composer at zero height. ExyteChat sizes the list's inset
    /// from this view, so a note with height would move the list each time it showed.
    private var footerAccessory: some View {
        Color.clear
            .frame(height: 0)
            .overlay(alignment: .bottom) {
                if viewModel.hasHeldMessages {
                    Text(.dailyChatSendingReassurance)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .padding(.horizontal, PaeoniaSpacing.space12)
                        .padding(.vertical, PaeoniaSpacing.space4)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, PaeoniaSpacing.space4)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.hasHeldMessages)
    }

    private var replyPreview: DailyChatReplyPreview? {
        guard let target = viewModel.replyTarget else { return nil }
        return DailyChatProjection.preview(of: target, id: target.id, input: projectionInput)
    }

    // MARK: - Waiting

    /// The page before both answers are revealed: the question, your answer, and who
    /// the chat is waiting for. It uses the same rows as the chat.
    private var waitingPage: some View {
        let projection = projection
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(projection.exyteMessages, id: \.id) { message in
                    if let row = projection.rowsByID[message.id] {
                        messageRow(row, messageFrame: nil)
                    }
                }
                if viewModel.question.ownAnswerDetail == nil, let sendingAnswer {
                    DailyChatSendingAnswerRow(answer: sendingAnswer)
                }
                if let waitingMessage = viewModel.waitingMessage {
                    Text(waitingMessage)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                        .padding(.top, PaeoniaSpacing.space16)
                }
            }
            .padding(.vertical, PaeoniaSpacing.space12)
        }
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

// MARK: - ExyteChat setup

private extension DailyQuestionChatView {
    var chatLocalization: ChatLocalization {
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

    var chatTheme: ChatTheme {
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
                inputBG: .paeoniaBackgroundPrimary,
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
}

extension DailyQuestionChatView {
    // MARK: - Actions

    private func retry(_ message: DailyQuestionChatMessage?) {
        guard let message, message.sendFailed else { return }
        Task {
            if message.voice != nil {
                await viewModel.resendVoice(message)
            } else if !(message.photos ?? []).isEmpty {
                await viewModel.resendPhotos(message)
            } else {
                _ = await viewModel.send(
                    message.body,
                    replacingFailed: message.clientOperationID,
                    replyToMessageID: message.replyToMessageID
                )
            }
        }
    }

    private func handleMenuAction(
        _ action: DailyChatMenuAction,
        _: (ExyteChat.Message, DefaultMessageMenuAction) -> Void,
        _ message: ExyteChat.Message
    ) {
        guard let row = projection.rowsByID[message.id] else { return }
        switch action {
        case .reply:
            if let target = row.message { viewModel.setReplyTarget(target) }
        case .copy:
            UIPasteboard.general.string = message.text
        case .report:
            switch row.kind {
            case let .answer(answer):
                onReport?(.dailyAnswer(answerID: answer.answerID))
            case let .message(target):
                onReport?(.threadMessage(messageID: target.id))
            case .question, .typing:
                break
            }
        }
    }

    /// Opens every photo in the chat in the full-screen viewer, at the tapped one, so a
    /// swipe goes through the rest. Like Tidex's chat gallery.
    private func openPhoto(_ tapped: DailyQuestionChatPhoto) {
        let photos = viewModel.messages.flatMap { $0.photos ?? [] }
        let items = photos.compactMap { photo -> PaeoniaImageViewerItem? in
            guard let key = DailyChatPhotoLayout.cacheKey(for: photo) else { return nil }
            return PaeoniaImageViewerItem(
                id: key,
                image: nil,
                imageLoader: { await Self.fullImage(of: photo) }
            )
        }
        guard let initial = DailyChatPhotoLayout.cacheKey(for: tapped), !items.isEmpty else { return }
        photoViewer = PaeoniaImageViewerSelection(items: items, initialItemID: initial, allowsSaving: true)
    }

    /// The whole photo for the viewer, from this phone's copy or the downloaded file.
    @concurrent
    private nonisolated static func fullImage(of photo: DailyQuestionChatPhoto) async -> UIImage? {
        if let data = photo.data { return UIImage(data: data) }
        guard let mediaAssetID = photo.mediaAssetID,
              let data = await DailyAnswerMediaImageProviderFactory.shared?.imageData(for: mediaAssetID)
        else { return nil }
        return UIImage(data: data)
    }

    /// Tapping a quote scrolls to the message it answers and lights it up for a moment.
    private func jumpToMessage(_ messageID: UUID) {
        guard let target = viewModel.message(withID: messageID) else { return }
        let rowID = DailyChatProjection.rowID(for: target)
        scrollTarget = nil
        Task { @MainActor in
            scrollTarget = ScrollToParams(messageID: rowID, position: .middle)
            highlightedRowID = rowID
            try? await Task.sleep(for: Self.highlightDuration)
            if highlightedRowID == rowID { highlightedRowID = nil }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    /// The partner's answer row once the chat shows it.
    private var revealedPartnerAnswerRowID: String? {
        guard viewModel.isChatAvailable,
              let answer = viewModel.answers.first(where: { !$0.isOwnAnswer })
        else { return nil }
        return DailyChatProjection.answerRowPrefix + answer.answerID.uuidString
    }

    /// Right after answering, the partner's answer is the payoff, so it lights up
    /// like a jumped-to message, with the reveal haptic.
    private func revealPartnerAnswer() {
        guard revealsPartnerAnswer, !didRevealPartnerAnswer, let rowID = revealedPartnerAnswerRowID else { return }
        didRevealPartnerAnswer = true
        PaeoniaHaptics.answerRevealed()
        Task { @MainActor in
            highlightedRowID = rowID
            try? await Task.sleep(for: Self.highlightDuration)
            if highlightedRowID == rowID { highlightedRowID = nil }
        }
    }

    /// With only the question and answers there, the chat opens at the question, so
    /// the page reads from the start. Once anyone has written, it opens at the newest
    /// message. The chat is usually read before the screen opens, so this runs as the
    /// list first fills, not after it was shown.
    private func applyOpeningScroll() {
        guard !didApplyOpeningScroll, viewModel.hasReadStore else { return }
        didApplyOpeningScroll = true
        guard viewModel.messages.isEmpty else { return }
        scrollTarget = ScrollToParams(.oldestMessage)
    }

    private func handleBackgroundTimestampRevealChanged(_ value: DailyChatDragValue) {
        guard let offset = DailyChatTimestampRevealResolver.clampedRevealOffset(
            horizontal: value.translation.width,
            vertical: value.translation.height
        ) else { return }
        timestampRevealOffset = offset
    }

    private func handleBackgroundTimestampRevealEnded(_ value: DailyChatDragValue) {
        handleBackgroundTimestampRevealChanged(value)
        guard timestampRevealOffset != 0 else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            timestampRevealOffset = 0
        }
    }
}
