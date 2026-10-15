import ExyteChat
import SwiftUI

/// A question's own page, laid out like a group chat. A couple has one chat per
/// question, so the page stacks every day the question came up, oldest first. Each day
/// is Paeonia's question, then both answers as bubbles from the people who wrote them,
/// and the conversation follows in the order it happened. Until some day has both
/// answers revealed the page shows what is there and says who it is waiting for, with
/// no composer.
///
/// The chat follows Tidex's friends chat: the same ExyteChat setup, row gestures
/// (swipe to reply, swipe left for times, swipe right to go back), long-press menu,
/// and a composer of its own. The rows come from a cached `DailyChatProjection`, and
/// ExyteChat redraws only rows whose content changed, so scrolling stays smooth.
struct DailyQuestionChatView: View {
    private static let bottomComposerClearance: CGFloat = 14
    private static let highlightDuration: Duration = .seconds(1.6)
    /// Long enough for the reveal's build-up, bounce, sparkles, and petals to finish.
    private static let revealDuration: Duration = .seconds(2)

    @State private var viewModel: DailyQuestionChatViewModel
    let question: DailyChallengeQuestion
    let participants: DailyChallengeParticipants
    var onReport: ((PrivacyReportTarget) -> Void)?
    /// The user's answer while it is still sending, shown on the waiting page until
    /// this phone has it.
    var sendingAnswer: DailySendingPreview?
    /// Set when the page opens right after answering. The partner's answer plays its
    /// reveal when it shows, once.
    var revealsPartnerAnswer = false
    /// Swiping right calls this instead of `dismiss`, for a page that owns its cover.
    var onClose: (() -> Void)?
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoViewer: PaeoniaImageViewerSelection?
    @State private var projectionStore = DailyChatProjectionStore()
    @State private var timestampReveal = DailyChatTimestampReveal()
    @State private var highlightedRowID: String?
    /// The partner's answer row while it plays its reveal.
    @State private var revealingRowID: String?
    /// Where the list scrolls next. Nil keeps the list where it is.
    @State private var scrollTarget: ScrollToParams?
    @State private var didApplyOpeningScroll = false
    /// The page opened before the server's list of days arrived, so it scrolls once more
    /// when the list does.
    @State private var openedWithoutRounds = false
    @State private var didRevealPartnerAnswer = false
    /// The day whose partner-choice match plays its celebration, while the reveal plays.
    @State private var celebratingInstanceID: UUID?

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
        .onChange(of: viewModel.hasLoadedRounds) { applyOpeningScroll() }
        .onChange(of: revealedPartnerAnswerRowID, initial: true) { revealPartnerAnswer() }
        .paeoniaImageViewer(selection: $photoViewer)
    }

    private var projectionInput: DailyChatProjection.Input {
        DailyChatProjection.Input(
            rounds: viewModel.chatRounds(celebrating: celebratingInstanceID),
            messages: viewModel.messages,
            currentUserID: viewModel.participants.currentUserID,
            partnerName: viewModel.participants.partnerName,
            youName: String(localized: .dailyChallengeChoiceYou),
            partnerIsTyping: viewModel.presence.partnerIsTyping,
            partnerLastReadMessageID: viewModel.presence.partnerLastReadMessageID
        )
    }

    private var projection: DailyChatProjection {
        projectionStore.projection(for: projectionInput)
    }

    // MARK: - Chat

    private var chat: some View {
        let projection = projection
        return ChatView(
            messages: projection.highlighting(highlightedRowID, revealing: revealingRowID),
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
                    editingMessage: viewModel.editTarget,
                    focusRequest: viewModel.composerFocusRequest,
                    onCancelReply: viewModel.cancelReply,
                    onCancelEdit: viewModel.cancelEdit,
                    onSaveEdit: { await viewModel.saveEdit($0) },
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
        .enableLoadMoreOlderMessages(hasMoreToLoad: viewModel.hasOlderMessages) {
            await viewModel.loadOlderMessages()
        }
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
            isHighlighted: row.id == highlightedRowID,
            isRevealing: row.id == revealingRowID,
            onReply: row.message.flatMap { message in
                viewModel.canReply(to: message) ? { viewModel.setReplyTarget(message) } : nil
            },
            onRetry: { retry(row.message) },
            onTapQuoted: jumpToMessage,
            onOpenPhoto: openPhoto,
            timestampReveal: timestampReveal,
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

    /// The page before any day has both answers revealed: the question, your answer, and
    /// who the chat is waiting for. It uses the same rows as the chat.
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
            }
            .padding(.vertical, PaeoniaSpacing.space12)
        }
        // Rows sit at the bottom, where the chat stacks them, so they stay put when the
        // partner's answer arrives and the page turns into the chat.
        .defaultScrollAnchor(.bottom)
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
        case .edit:
            if let target = row.message { viewModel.startEditing(target) }
        case .copy:
            UIPasteboard.general.string = message.text
        case .report:
            report(row)
        }
    }

    private func report(_ row: DailyChatRow) {
        switch row.kind {
        case let .answer(answer, _):
            onReport?(.dailyAnswer(answerID: answer.answerID))
        case let .message(target):
            onReport?(.threadMessage(messageID: target.id))
        case .question, .partnerChoiceMatch, .waiting, .typing:
            break
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
        photoViewer = PaeoniaImageViewerSelection(items: items, initialItemID: initial)
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

    /// The day the page was opened from, when the chat shows its partner's answer.
    private var revealedRound: DailyChallengeQuestion? {
        guard viewModel.isChatAvailable,
              let round = viewModel.rounds.first(where: { $0.id == viewModel.question.id }),
              round.partnerAnswerDetail?.canViewAnswer == true
        else { return nil }
        return round
    }

    /// The partner's answer row of that day once the chat shows it.
    private var revealedPartnerAnswerRowID: String? {
        revealedRound?.partnerAnswerDetail.map { DailyChatProjection.answerRowPrefix + $0.answerID.uuidString }
    }

    /// Right after answering, the partner's answer is the payoff, so its bubble plays
    /// the reveal, haptics included (`dailyChatAnswerReveal`). A partner-choice match
    /// plays its small celebration with it.
    private func revealPartnerAnswer() {
        guard revealsPartnerAnswer, !didRevealPartnerAnswer, let rowID = revealedPartnerAnswerRowID else { return }
        didRevealPartnerAnswer = true
        celebratingInstanceID = revealedRound?.id
        revealingRowID = rowID
        Task { @MainActor in
            try? await Task.sleep(for: Self.revealDuration)
            if revealingRowID == rowID { revealingRowID = nil }
            celebratingInstanceID = nil
        }
    }

    /// The page opens on the day it was opened from, or on the newest message when people
    /// have written since that day began. The chat is usually read before the screen
    /// opens, so this runs as the list first fills, not after it was shown. A page that
    /// opened before the server's list of days arrived scrolls again when the list does.
    private func applyOpeningScroll() {
        guard viewModel.hasReadStore else { return }
        if !didApplyOpeningScroll {
            didApplyOpeningScroll = true
            openedWithoutRounds = !viewModel.hasLoadedRounds
        } else if openedWithoutRounds, viewModel.hasLoadedRounds {
            openedWithoutRounds = false
        } else {
            return
        }
        switch viewModel.openingScroll {
        case .newestMessage:
            break
        case .oldestRow:
            scrollTarget = ScrollToParams(.oldestMessage)
        case let .questionRow(instanceID):
            scrollTarget = ScrollToParams(
                messageID: DailyChatProjection.questionRowID(for: instanceID),
                position: .middle
            )
        }
    }

    private func handleBackgroundTimestampRevealChanged(_ value: DailyChatDragValue) {
        guard let offset = DailyChatTimestampRevealResolver.clampedRevealOffset(
            horizontal: value.translation.width,
            vertical: value.translation.height
        ) else { return }
        timestampReveal.offset = offset
    }

    private func handleBackgroundTimestampRevealEnded(_ value: DailyChatDragValue) {
        handleBackgroundTimestampRevealChanged(value)
        guard timestampReveal.offset != 0 else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            timestampReveal.offset = 0
        }
    }
}
