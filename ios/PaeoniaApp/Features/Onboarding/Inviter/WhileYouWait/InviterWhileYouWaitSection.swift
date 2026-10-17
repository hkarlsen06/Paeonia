import SwiftUI

/// Two things the inviter can make for their partner while the code is out: their first
/// answers and a drawing for the partner's Home Screen. It sits under the code as a
/// quiet invitation. Each row shows how far it got, and plays a small beat with hearts
/// when it turns done. The rows open the answer flow and the drawing screen as
/// full-screen covers.
struct InviterWhileYouWaitSection: View {
    let model: InviterFirstDayModel

    @State private var questionsModel: FirstDayQuestionsModel?
    /// The answers the flow closed with, applied once the cover is gone so the
    /// completion beat plays on this screen.
    @State private var closedQuestions: [FirstDayQuestion]?
    @State private var isDrawing = false
    @State private var isOpeningQuestions = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            header
                .screenEntrance(order: 1, isReady: model.hasLoaded)
            // The ids let the invite screen scroll a row into sight for its completion beat.
            questionsRow
                .id(InviterFirstDayModel.Item.questions)
                .screenEntrance(order: 2, isReady: model.hasLoaded)
            drawingRow
                .id(InviterFirstDayModel.Item.drawing)
                .screenEntrance(order: 3, isReady: model.hasLoaded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshOnForeground() }
            }
        }
        .onChange(of: model.loadFailure) { _, failure in
            guard let failure else {
                return
            }
            bannerCenter.show(.error(
                title: String(localized: .inviterQuestionsLoadFailedTitle),
                message: String(
                    localized: failure == .offline
                        ? .inviterQuestionsLoadFailedOfflineMessage
                        : .commonActionFailedMessage
                )
            ))
            model.clearLoadFailure()
        }
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
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
            PaeoniaCardEyebrow(.inviterWhileYouWaitTitle)

            Text(.inviterWhileYouWaitMessage)
                .font(PaeoniaTypography.caption)
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
