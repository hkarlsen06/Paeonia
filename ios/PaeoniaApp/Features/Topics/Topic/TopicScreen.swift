import SwiftUI

/// One topic: its picture and progress, then its questions grouped by where they
/// stand. What waits for this person comes on top: partner answers and messages they
/// haven't opened, then questions the partner answered first. Then the ones nobody has
/// started, the ones waiting for the partner, the ones answered together, and a
/// collapsed list of skipped ones. "Answer the next one" opens the next question.
struct TopicScreen: View {
    let topicKey: String
    let viewModel: TopicsViewModel
    let dailyChallenge: DailyChallengeViewModel
    var zoomNamespace: Namespace.ID?
    /// Opens the answer flow for a question, as a cover that zooms out of its row.
    let onAnswer: (DailyChallengeQuestion) -> Void
    /// Opens the question's page with both answers and the chat.
    let onOpenChat: (DailyChallengeQuestion) -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSkipped = false

    private var participants: DailyChallengeParticipants {
        dailyChallenge.participants
    }

    private var topic: TopicSummary? {
        viewModel.topic(topicKey)
    }

    private var sections: TopicSections {
        viewModel.sections(for: topicKey)
    }

    var body: some View {
        content
            .paeoniaTabBackdrop()
            .paeoniaFittingNavigationTitle(Text(verbatim: topic?.title ?? ""))
            .safeAreaInset(edge: .bottom) { answerNextBar }
            .overlay {
                if viewModel.celebratingTopicKey == topicKey, let topic {
                    TopicFinishedView(topic: topic, onDone: viewModel.finishCelebration)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : PaeoniaMotion.meaningfulMoment, value: viewModel.celebratingTopicKey)
            // The view model keeps following it under the answer cover and the chat.
            .onAppear { viewModel.open(topicKey) }
            .onChange(of: viewModel.items[topicKey]?.count, initial: true) {
                viewModel.markShown(topicKey)
            }
            .onChange(of: viewModel.notice) { _, notice in
                guard let notice else { return }
                bannerCenter.show(notice.banner)
                viewModel.dismissNotice()
            }
            .analyticsScreen("topic")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.items[topicKey] != nil {
            list
        } else if let failure = viewModel.failedTopics[topicKey] {
            PaeoniaLoadFailureView(failure: failure, offlineMessage: .topicsLoadOfflineMessage) {
                Button {
                    viewModel.retry(topicKey)
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle())
            }
        } else {
            ProgressView()
                .tint(.paeoniaAccentPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        let sections = sections
        return ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                header

                forYouSection(sections)
                section(.topicsSectionUpNext, sections.upNext, opensFlow: true)
                section(.topicsSectionWaiting(participants.partnerName), sections.waitingForPartner, opensFlow: false)
                section(.topicsSectionTogether, sections.together, opensFlow: false)
                skippedSection(sections.skipped)
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.sectionSpacing)
            .paeoniaReadableWidth(alignment: .leading)
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: sectionIDs(sections))
        }
    }

    private var header: some View {
        let tint = TopicStyle.tint(for: topicKey)
        return VStack(spacing: PaeoniaSpacing.space8) {
            TopicArtwork(topicKey: topicKey, height: 128)
                .frame(height: 140)
                .padding(.top, PaeoniaSpacing.space8)
            if let topic {
                Text(topic.title)
                    .font(PaeoniaTypography.collectionHeroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(topic.subtitle)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                TopicProgressLine(topic: topic, ringSize: 18)
                    .padding(.top, PaeoniaSpacing.space4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, PaeoniaSpacing.space16)
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// Partner answers and messages to open, which open the question's page, then
    /// questions to answer, which open the answer flow.
    @ViewBuilder
    private func forYouSection(_ sections: TopicSections) -> some View {
        if !sections.waiting.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                sectionTitle(Text(.topicsSectionForYou))
                ForEach(sections.newFromPartner) { item in
                    row(item, opensFlow: false)
                }
                ForEach(sections.forYou) { item in
                    row(item, opensFlow: true)
                }
            }
        }
    }

    @ViewBuilder
    private func section(
        _ title: LocalizedStringResource,
        _ items: [TopicQuestionItem],
        opensFlow: Bool
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                sectionTitle(Text(title))
                ForEach(items) { item in
                    row(item, opensFlow: opensFlow)
                }
            }
        }
    }

    private func row(_ item: TopicQuestionItem, opensFlow: Bool) -> some View {
        let question = dailyChallenge.latestQuestion(item.question)
        let isSending = dailyChallenge.isSending(item.id)
        let state = item.state(isSending: isSending)
        return Button {
            if opensFlow {
                onAnswer(question)
            } else if !isSending {
                onOpenChat(question)
            }
        } label: {
            TopicQuestionRow(
                item: item,
                state: state,
                partnerName: participants.partnerName,
                partnerPhotoAssetID: participants.partnerProfilePhotoAssetID,
                chatPreview: dailyChallenge.threadPreview(for: question.questionID),
                isNew: dailyChallenge.hasNewFromPartner(question),
                isSending: isSending
            )
        }
        .buttonStyle(.paeoniaPressableRow)
        .zoomSource(item.id, in: opensFlow ? zoomNamespace : nil)
        .id(item.id)
    }

    @ViewBuilder
    private func skippedSection(_ items: [TopicQuestionItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Button {
                    withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) { showsSkipped.toggle() }
                } label: {
                    HStack(spacing: PaeoniaSpacing.space4) {
                        sectionTitle(Text(.topicsSectionSkipped(items.count)))
                        Image(systemName: "chevron.down")
                            .font(PaeoniaTypography.caption.weight(.semibold))
                            .foregroundStyle(.paeoniaTextTertiary)
                            .rotationEffect(.degrees(showsSkipped ? 0 : -90))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsSkipped {
                    ForEach(items) { item in
                        TopicQuestionRow(
                            item: item,
                            state: .skipped,
                            partnerName: participants.partnerName,
                            partnerPhotoAssetID: participants.partnerProfilePhotoAssetID,
                            onBringBack: {
                                Task { await viewModel.setSkipped(item.question, skipped: false) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(PaeoniaTypography.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityAddTraits(.isHeader)
    }

    /// "Answer the next one", while there is a question left to answer.
    @ViewBuilder
    private var answerNextBar: some View {
        if viewModel.items[topicKey] != nil, let next = sections.nextToAnswer {
            Button {
                onAnswer(dailyChallenge.latestQuestion(next.question))
            } label: {
                Text(.topicsAnswerNext)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.bottom, PaeoniaSpacing.space8)
            .paeoniaReadableWidth()
            .accessibilityIdentifier("topics.answerNext")
        }
    }

    private func sectionIDs(_ sections: TopicSections) -> [[UUID]] {
        [
            sections.newFromPartner,
            sections.forYou,
            sections.upNext,
            sections.waitingForPartner,
            sections.together,
            sections.skipped,
        ]
            .map { $0.map(\.id) }
    }
}
