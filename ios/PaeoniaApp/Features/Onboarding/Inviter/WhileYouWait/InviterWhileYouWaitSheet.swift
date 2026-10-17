import SwiftUI

/// Two things the inviter can make for their partner while the code is out: their first
/// answers and a drawing for the partner's Home Screen. The invite screen's "While you
/// wait" button opens this sheet. Each row shows how far it got, and plays a small beat
/// with hearts when it turns done. The rows open the answer flow and the drawing screen
/// as full-screen covers.
struct InviterWhileYouWaitSheet: View {
    let model: InviterFirstDayModel

    @State private var questionsModel: FirstDayQuestionsModel?
    /// The answers the flow closed with, applied once the cover is gone so the
    /// completion beat plays on this screen.
    @State private var closedQuestions: [FirstDayQuestion]?
    @State private var isDrawing = false
    @State private var isOpeningQuestions = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
                header
                    .screenEntrance(order: 1)

                VStack(spacing: PaeoniaSpacing.space12) {
                    questionsRow
                        .screenEntrance(order: 2)
                    drawingRow
                        .screenEntrance(order: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space32)
            .padding(.bottom, PaeoniaSpacing.space16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paeoniaScreenBackground()
        // The sheet covers the root's banner, so it mounts its own copy.
        .paeoniaTopBanner(bannerCenter)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: model.completion) { _, completion in
            guard completion != nil else {
                return
            }
            PaeoniaHaptics.firstDayItemDone()
            GameSound.chime.play()
        }
        .fullScreenCover(item: $questionsModel, onDismiss: questionsClosed) { questionsModel in
            FirstDayQuestionsFlow(model: questionsModel) { questions in
                closedQuestions = questions
                self.questionsModel = nil
            }
            .environment(bannerCenter)
            .paeoniaTopBanner(bannerCenter)
        }
        .fullScreenCover(isPresented: $isDrawing, onDismiss: drawingClosed) {
            FirstDayDrawingFlow(model: model) {
                isDrawing = false
            }
            .environment(bannerCenter)
            .paeoniaTopBanner(bannerCenter)
        }
    }

    // MARK: Rows

    private var header: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Text(.inviterWhileYouWaitTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(.inviterWhileYouWaitMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var questionsRow: some View {
        InviterFirstDayRow(
            title: .inviterQuestionsRowTitle,
            subtitle: model.hasAnsweredQuestions ? .inviterQuestionsRowDone : .inviterQuestionsRowSubtitle,
            isDone: model.hasAnsweredQuestions,
            completion: model.completion?.item == .questions ? model.completion : nil,
            action: openQuestions
        ) {
            InviterFirstDayRowIcon(systemImage: "text.bubble.fill")
        } trailing: {
            InviterQuestionsProgress(
                answered: model.draft?.answeredCount ?? 0,
                total: model.draft?.questions.count ?? 0,
                isLoading: isOpeningQuestions
            )
        }
    }

    private var drawingRow: some View {
        InviterFirstDayRow(
            title: .inviterDrawingRowTitle,
            subtitle: drawingSubtitle,
            isDone: model.hasDrawing,
            completion: model.completion?.item == .drawing ? model.completion : nil,
            action: openDrawing
        ) {
            if let thumbnail = model.drawingThumbnail {
                InviterDrawingThumbnail(image: thumbnail)
            } else {
                InviterFirstDayRowIcon(systemImage: "scribble.variable")
            }
        } trailing: {
            InviterFirstDayCheck(isDone: model.hasDrawing)
        }
    }

    private var drawingSubtitle: LocalizedStringResource {
        if model.isDrawingWaiting {
            .inviterDrawingRowWaiting
        } else if model.hasDrawing {
            .inviterDrawingRowDone
        } else {
            .inviterDrawingRowSubtitle
        }
    }

    // MARK: Actions

    private func openQuestions() {
        guard !isOpeningQuestions else {
            return
        }
        isOpeningQuestions = true
        Task {
            questionsModel = await model.makeQuestionsModel()
            isOpeningQuestions = false
        }
    }

    private func questionsClosed() {
        guard let closedQuestions else {
            return
        }
        self.closedQuestions = nil
        model.questionsFlowClosed(with: closedQuestions)
        Task { await model.refreshNotificationPermission() }
    }

    private func openDrawing() {
        isDrawing = true
    }

    private func drawingClosed() {
        Task { await model.drawingFlowClosed() }
    }
}
