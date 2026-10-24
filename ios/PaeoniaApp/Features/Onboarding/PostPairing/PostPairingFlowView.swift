import SwiftUI

/// The first day sequence after the pairing celebration: unwrap what the partner
/// made, draw back, confirm the date, pick question time, and answer. Each step
/// crossfades into the next, and every step can be skipped. The root shows this
/// in place of the tabs until `onFinish`.
struct PostPairingFlowView: View {
    let model: PostPairingFlowModel
    let partnerName: String
    let currentDisplayName: String?
    /// The couple's start date as `yyyy-MM-dd`, as the server has it now.
    let startedOn: String?
    /// This person joined with the partner's code.
    let acceptedInvite: Bool
    let syncAfterLocalChange: @MainActor () async -> Void
    let onFinish: (PostPairingOutcome) -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    /// Long enough to see the drawing screen say it was sent.
    private static let sentPause: Duration = .seconds(0.9)

    var body: some View {
        NavigationStack {
            ZStack {
                if let screen = model.screen {
                    screenView(screen)
                        .analyticsScreen("post_pairing_\(screen)")
                        .id(screen)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A step that changes under the drawing screen swaps at once, so going
            // back lands on it instead of watching the gift fade out.
            .animation(model.drawingViewModel == nil ? PaeoniaMotion.meaningfulMoment : nil, value: model.screen)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: drawingPresented) {
                if let drawingViewModel = model.drawingViewModel {
                    WidgetDrawingView(viewModel: drawingViewModel)
                }
            }
        }
        .task(id: model.context?.pairID) {
            await model.start(startedOn: startedOn, acceptedInvite: acceptedInvite)
        }
        .onChange(of: model.outcome) { _, outcome in
            if let outcome {
                onFinish(outcome)
            }
        }
        .onChange(of: model.giftFailure) { _, failure in
            guard let failure else {
                return
            }
            showGiftFailure(failure)
            model.clearGiftFailure()
        }
        .onChange(of: model.drawingViewModel?.delivery) { oldDelivery, delivery in
            // Only a send from this screen. Opening it can restore `.waiting` for
            // an older drawing that is still queued.
            guard oldDelivery == .sending, delivery == .sent || delivery == .waiting else {
                return
            }
            Task {
                try? await Task.sleep(for: Self.sentPause)
                await model.drawingSent()
            }
        }
    }

    @ViewBuilder
    private func screenView(_ screen: PostPairingFlowModel.Screen) -> some View {
        switch screen {
        case .gift:
            if let gift = model.gift {
                PostPairingGiftStep(
                    model: gift,
                    partnerName: partnerName,
                    onOpen: { model.giftOpened() },
                    onDrawBack: { model.drawBack(authorName: currentDisplayName) },
                    onLater: { model.giftLater() }
                )
            }
        case .widgetNudge:
            if let image = model.nudgeDrawing {
                WidgetNudgeStep(
                    drawing: image,
                    authorName: currentDisplayName,
                    placement: .standalone,
                    onFinish: { _ in model.widgetNudgeFinished() }
                )
            }
        case .date:
            dateStep
        case .questionTime:
            QuestionTimeStep(
                context: .paired,
                placement: .standalone,
                model: model.makeQuestionTimeModel(),
                onFinish: { _ in model.questionTimeFinished() }
            )
        case .answerInvite:
            PostPairingAnswerInviteStep(partnerName: partnerName) { answerNow in
                model.answerInviteFinished(answerNow: answerNow)
            }
        }
    }

    @ViewBuilder
    private var dateStep: some View {
        if let ownerUserID = model.context?.currentUserID {
            PostPairingDateStep(
                startedOn: startedOn,
                confirmsPartnerDate: model.acceptedInvite,
                partnerName: partnerName,
                ownerUserID: ownerUserID,
                milestone: model.makeMilestoneViewModel(),
                syncAfterLocalChange: { await syncAfterLocalChange() },
                onFinish: { model.dateFinished() }
            )
        }
    }

    /// Open while the drawing screen is. Going back without sending moves on.
    private var drawingPresented: Binding<Bool> {
        Binding(
            get: { model.drawingViewModel != nil },
            set: { isPresented in
                if !isPresented {
                    model.drawingClosed()
                }
            }
        )
    }

    private func showGiftFailure(_ failure: PaeoniaFailure) {
        bannerCenter.show(.error(
            title: String(localized: .onboardingFirstDayGiftFailedTitle(partnerName)),
            message: String(
                localized: failure == .offline
                    ? .onboardingFirstDayGiftFailedOfflineMessage
                    : .onboardingFirstDayGiftFailedMessage
            )
        ))
    }
}
