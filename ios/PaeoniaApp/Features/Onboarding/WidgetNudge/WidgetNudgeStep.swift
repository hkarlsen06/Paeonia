import SwiftUI
import UIKit

/// Shown right after the person drew their first drawing. It shows the drawing on a
/// picture of the Home Screen widget and walks them through adding the real one.
///
/// The step looks for the widget when it appears and each time the app comes back to
/// the front. Once it finds it, the step celebrates and offers Continue. Before that
/// the only choice is the quiet "I'll do it later". `onFinish` gets whether the
/// widget was added. To skip the step for someone who already has the widget, check
/// `WidgetNudgeModel.isWidgetInstalled()` first.
struct WidgetNudgeStep: View {
    let drawing: UIImage
    let authorName: String?
    let placement: OnboardingStepPlacement
    let onFinish: (_ added: Bool) -> Void

    @State private var model: WidgetNudgeModel
    @State private var activeStep = 0
    @State private var bloomStart: Date?
    @State private var hasFinished = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stepInterval: Duration = .seconds(2.4)

    init(
        drawing: UIImage,
        authorName: String? = nil,
        placement: OnboardingStepPlacement = .brandedFrame,
        model: WidgetNudgeModel = WidgetNudgeModel(),
        onFinish: @escaping (_ added: Bool) -> Void
    ) {
        self.drawing = drawing
        self.authorName = authorName
        self.placement = placement
        self.onFinish = onFinish
        _model = State(initialValue: model)
    }

    /// The how-to plays on a loop until the widget is found. Reduce Motion keeps it still.
    private var playsSteps: Bool {
        !reduceMotion && !model.isAdded
    }

    var body: some View {
        OnboardingStepScaffold(
            title: model.isAdded ? .onboardingWidgetNudgeAddedTitle : .onboardingWidgetNudgeTitle,
            message: model.isAdded ? .onboardingWidgetNudgeAddedMessage : .onboardingWidgetNudgeMessage,
            placement: placement,
            primary: model.isAdded
                ? OnboardingStepAction(title: .onboardingWidgetNudgeContinueButton) { finish(added: true) }
                : nil,
            secondary: model.isAdded
                ? nil
                : OnboardingStepAction(title: .onboardingWidgetNudgeLaterButton) { finish(added: false) }
        ) {
            WidgetHomeScreenMock(
                drawing: drawing,
                authorName: authorName,
                activeStep: playsSteps ? activeStep : nil,
                isAdded: model.isAdded
            )
            .frame(maxWidth: 230)
            .overlay {
                if let bloomStart {
                    GamePetalBloom(start: bloomStart, seed: "onboarding.widgetAdded", origin: UnitPoint(x: 0.5, y: 0.4))
                        .padding(-PaeoniaSpacing.space40)
                }
            }
        } content: {
            if !model.isAdded {
                WidgetNudgeHowTo(activeStep: playsSteps ? activeStep : nil)
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: model.isAdded)
        // Runs on appear and again each time the app comes back, since adding the
        // widget means leaving the app.
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }
            let found = await model.checkAfterReturning()
            guard found, !Task.isCancelled else {
                return
            }
            celebrate()
        }
        .task(id: playsSteps) {
            await playSteps()
        }
    }

    private func playSteps() async {
        guard playsSteps else {
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.stepInterval)
            guard !Task.isCancelled else {
                return
            }
            activeStep = (activeStep + 1) % WidgetNudgeHowTo.stepCount
        }
    }

    private func celebrate() {
        guard !hasFinished else {
            return
        }
        PaeoniaHaptics.widgetAdded()
        GameSound.win.play()
        if !reduceMotion {
            bloomStart = Date()
        }
        AccessibilityNotification.Announcement(
            String(localized: .onboardingWidgetNudgeAddedTitle)
        ).post()
    }

    private func finish(added: Bool) {
        guard !hasFinished else {
            return
        }
        hasFinished = true
        if added {
            PaeoniaHaptics.celebrationContinued()
        }
        onFinish(added)
    }
}

#if DEBUG
/// Says the widget is there after a few seconds, so the preview shows the success beat.
nonisolated private struct PreviewWidgetConfigurations: WidgetConfigurationProviding {
    let addedAt = Date().addingTimeInterval(6)

    // swiftlint:disable:next async_without_await
    func installedWidgetKinds() async throws -> [String] {
        Date() > addedAt ? [PaeoniaAppGroup.widgetKind] : []
    }
}

#Preview("Waiting, then added") {
    WidgetNudgeStep(
        drawing: UIImage(resource: .placeholderSketch),
        authorName: "Hjalmar",
        placement: .standalone,
        model: WidgetNudgeModel(configurations: PreviewWidgetConfigurations(), recheckDelay: .seconds(7)),
        onFinish: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("In the branded frame") {
    RootBrandedFrame {
        WidgetNudgeStep(
            drawing: UIImage(resource: .placeholderSketch),
            authorName: "Elena",
            onFinish: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
