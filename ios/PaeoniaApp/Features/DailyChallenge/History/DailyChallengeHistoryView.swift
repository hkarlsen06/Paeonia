import SwiftUI

/// A full-screen history of the couple's daily questions: the partner's questions
/// still waiting for the user's answer sit at the top with the same answer CTA the
/// Questions tab uses, and the completed exchanges follow, grouped by the day they
/// belong to (newest first) with a centered date divider between groups.
///
/// It reuses the same question card the Questions tab shows, so a past exchange reads
/// back exactly as it does on the day. Answering a waiting partner question opens the
/// focused flow zoomed out of its card; the completed exchanges below are read-only.
struct DailyChallengeHistoryView: View {
    @State private var viewModel: DailyChallengeHistoryViewModel
    /// The shared daily challenge view model, used to answer a partner's waiting
    /// question from here (the focused flow needs it) and to gate that CTA behind
    /// finishing today's own questions — the same rule the Questions tab applies.
    private let dailyChallengeViewModel: DailyChallengeViewModel
    private let privacySafetyService: (any PrivacySafetyServicing)?
    private let privacyOperationProvider: (any SyncClientOperationProviding)?
    private let onReportedAndLeft: () -> Void
    /// The question whose answer flow is open, presented over the history. Driving it
    /// by item lets the flow zoom out of the tapped card and carry its own state.
    @State private var answeringQuestion: DailyChallengeQuestion?
    @State private var reportedPartnerAnswerID: UUID?
    @State private var chattingQuestion: DailyChallengeQuestion?
    /// Source namespace for the answer flow's zoom-out transition; the tapped card marks
    /// itself in it so the flow appears to grow from the card the user tapped.
    @Namespace private var zoomNamespace
    /// How far the cover has followed a rightward exit swipe. Clamped to `>= 0` so the
    /// cover only ever slides toward the trailing edge, mirroring the system back-swipe a
    /// navigation push would give us — `fullScreenCover` has no interactive dismiss of its own.
    @State private var dismissDragOffset: CGFloat = 0

    /// Width of the leading-edge strip that arms the exit swipe, matching the system
    /// back-swipe affordance so the gesture never competes with the timeline's scroll.
    private static let edgeSwipeWidth: CGFloat = 20
    /// How far the cover must travel (or be flung) before lifting the finger dismisses it.
    private static let dismissThreshold: CGFloat = 96

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    init(
        viewModel: DailyChallengeHistoryViewModel,
        dailyChallengeViewModel: DailyChallengeViewModel,
        privacySafetyService: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault(),
        privacyOperationProvider: (any SyncClientOperationProviding)? = nil,
        onReportedAndLeft: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.dailyChallengeViewModel = dailyChallengeViewModel
        self.privacySafetyService = privacySafetyService
        self.privacyOperationProvider = privacyOperationProvider
        self.onReportedAndLeft = onReportedAndLeft
    }

    /// Keep full-screen cover insertion in the same transaction as the native zoom.
    /// Without an explicit transaction, SwiftUI can briefly draw the destination at its
    /// final full-screen size before the zoom animator takes over.
    private var zoomPresentationAnimation: Animation? {
        reduceMotion ? nil : PaeoniaMotion.heroMorph
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // The brand background fills the gap the cover reveals as it slides right,
            // so a part-way exit swipe never flashes black behind the content.
            Color.paeoniaBackgroundPrimary
                .ignoresSafeArea()

            NavigationStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.paeoniaBackgroundPrimary)
                    .navigationTitle(Text(.dailyChallengeHistoryTitle))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(Text(.dailyChallengeFlowClose))
                        }
                    }
                    .navigationDestination(item: $reportedPartnerAnswerID) { answerID in
                        if let partnerUserID = viewModel.participants.partnerUserID {
                            ReportAndLeaveView(
                                partnerUserID: partnerUserID,
                                partnerName: viewModel.participants.partnerName,
                                reportTarget: .dailyAnswer(answerID: answerID),
                                service: privacySafetyService,
                                operationProvider: privacyOperationProvider,
                                onReportedAndLeft: onReportedAndLeft
                            )
                        }
                    }
                    .navigationDestination(item: $chattingQuestion) { question in
                        DailyQuestionChatView(
                            viewModel: dailyChallengeViewModel.makeChatViewModel(question: question),
                            participants: dailyChallengeViewModel.participants
                        )
                    }
            }
            .offset(x: dismissDragOffset)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.86), value: dismissDragOffset)

            // A fixed, transparent leading-edge strip owns the exit swipe so it stays clear
            // of the timeline's vertical scroll and the cards' own taps.
            edgeSwipeCatcher
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
        .onChange(of: chattingQuestion) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            Task { await viewModel.refreshThreadSummaries() }
        }
        // Answering a waiting partner question zooms its card out into the focused
        // flow. Sending updates the shared challenge, so on close we reload the history
        // and the question moves from "waiting for you" into the completed timeline.
        .fullScreenCover(item: $answeringQuestion) { question in
            DailyPartnerAnswerFlow(
                question: question,
                viewModel: dailyChallengeViewModel,
                onClose: closeAnswerFlow
            )
            .zoomTransition(question.id, in: zoomNamespace, enabled: !reduceMotion)
            .environment(bannerCenter)
        }
    }

    /// The transparent leading-edge target for the exit swipe. It sits outside the
    /// offset content so it stays anchored at the edge and keeps receiving the drag even
    /// as the cover slides away under the finger.
    private var edgeSwipeCatcher: some View {
        Color.clear
            .frame(width: Self.edgeSwipeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(exitSwipe)
            .accessibilityHidden(true)
    }

    /// A rightward drag started from the leading edge: the cover follows the finger, and
    /// releasing past the threshold (or with a fling) dismisses it like a navigation pop.
    private var exitSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dismissDragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                let traveled = value.translation.width
                let flung = value.predictedEndTranslation.width
                if traveled > Self.dismissThreshold || flung > Self.dismissThreshold * 3 {
                    dismiss()
                } else {
                    // Didn't make it — settle the cover back into place.
                    dismissDragOffset = 0
                }
            }
    }

    private var content: some View {
        ZStack {
            switch viewModel.state {
            case .loading:
                // Calm loading surface until the first load settles, so the screen never
                // flashes the empty state before content arrives.
                ProgressView()
                    .controlSize(.large)
                    .tint(.paeoniaAccentPrimary)
            case .failed:
                failedState
            case .empty:
                emptyState
            case let .content(content):
                timeline(content)
            }
        }
        // The spinner dissolves into the timeline (or empty/error state) instead of
        // being swapped in one frame. A fade only, so Reduce Motion needs no branch.
        .animation(PaeoniaMotion.stateChange, value: viewModel.state)
    }

    private func timeline(_ content: DailyChallengeHistoryViewModel.Content) -> some View {
        ScrollView {
            LazyVStack(spacing: PaeoniaSpacing.sectionSpacing) {
                if !content.pendingPartnerQuestions.isEmpty {
                    pendingSection(content.pendingPartnerQuestions)
                }

                ForEach(content.days) { day in
                    VStack(spacing: PaeoniaSpacing.space12) {
                        DailyChallengeHistoryDateDivider(date: day.date)

                        ForEach(day.questions) { question in
                            DailyChallengeReadCard(
                                question: question,
                                participants: viewModel.participants,
                                onReportPartnerAnswer: { reportedPartnerAnswerID = $0 },
                                lastMessagePreview: viewModel.threadPreview(for: question.id),
                                onOpenChat: question.isChatAvailable
                                    ? { chattingQuestion = question }
                                    : nil
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space16)
            .padding(.bottom, PaeoniaSpacing.space32)
        }
        .refreshable { await viewModel.load() }
    }

    /// The partner's questions still waiting for the user's answer, shown at the top
    /// with the same CTA the Questions tab uses. The CTA stays visible but locked until
    /// the user finishes their own questions for the day.
    private func pendingSection(_ questions: [DailyChallengeQuestion]) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.dailyChallengePartnerSectionTitle(viewModel.participants.partnerName))
                .font(PaeoniaTypography.sectionTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(questions) { question in
                DailyChallengeReadCard(
                    question: question,
                    participants: viewModel.participants,
                    isOwnChallengeComplete: dailyChallengeViewModel.hasCompletedRequiredDailyQuestions,
                    zoomNamespace: zoomNamespace,
                    onAnswer: { openAnswerFlow(for: question) }
                )
            }
        }
    }

    private var emptyState: some View {
        PaeoniaEmptyStateView(
            title: .dailyChallengeHistoryEmptyTitle,
            message: .dailyChallengeHistoryEmptyMessage,
            systemImage: "clock.arrow.circlepath"
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    private var failedState: some View {
        PaeoniaEmptyStateView(
            title: .dailyChallengeHistoryLoadFailedTitle,
            message: .dailyChallengeHistoryLoadFailedMessage,
            systemImage: "exclamationmark.triangle"
        ) {
            Button {
                Task { await viewModel.load() }
            } label: {
                Text(.dailyChallengeHistoryRetryButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }

    /// Closes the partner-answer flow and refreshes the history so the just-answered
    /// question leaves the "waiting for you" section and joins the completed timeline.
    private func closeAnswerFlow() {
        answeringQuestion = nil
        Task { await viewModel.load() }
    }

    private func openAnswerFlow(for question: DailyChallengeQuestion) {
        withAnimation(zoomPresentationAnimation) {
            answeringQuestion = question
        }
    }

    private func showBanner(for notice: DailyChallengeHistoryViewModel.Notice?) {
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

/// A chat-style date divider: the localized day centered between two thin rules,
/// setting a gentle beat between one day's questions and the next. The date is
/// formatted in UTC so the displayed day matches the couple's local date exactly,
/// regardless of where the reader currently is.
struct DailyChallengeHistoryDateDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            rule

            Text(date, format: dateFormat)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize()

            rule
        }
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        Rectangle()
            .fill(.paeoniaSurfacePressed)
            .frame(height: PaeoniaRadius.strokeDefault)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .gmt)
    }
}

#if DEBUG
#Preview {
    DailyChallengeHistoryPreviewHost()
}

private struct DailyChallengeHistoryPreviewHost: View {
    @State private var dailyChallengeViewModel = DailyChallengeViewModel(service: PreviewDailyChallengeService())

    var body: some View {
        DailyChallengeHistoryView(
            viewModel: DailyChallengeHistoryViewModel(
                service: PreviewDailyChallengeService(),
                currentUserID: PreviewDailyChallengeService.userID,
                participants: DailyChallengeParticipants(
                    currentUserID: PreviewDailyChallengeService.userID,
                    currentDisplayName: "Hjalmar",
                    partnerUserID: UUID(),
                    partnerDisplayName: "Oda"
                )
            ),
            dailyChallengeViewModel: dailyChallengeViewModel
        )
        .environment(PaeoniaBannerCenter())
        .preferredColorScheme(.dark)
        .task { await dailyChallengeViewModel.configure(currentUserID: PreviewDailyChallengeService.userID) }
    }
}
#endif
