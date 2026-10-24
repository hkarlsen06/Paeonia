import SwiftUI
import UIKit

/// The second step of starting a couple, before sign-in: a first drawing for the
/// partner's Home Screen, on the same drawing screen used every day. Send saves it on
/// this phone and then shows it landing on a picture of a Home Screen. It goes out
/// after sign-in, from the invite screen. Skip moves on without a drawing.
struct WelcomeDrawingStep: View {
    let model: WelcomeFlowModel

    @State private var drawingViewModel: WidgetDrawingViewModel
    /// The sent drawing, once it shows on the Home Screen picture.
    @State private var landedDrawing: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: WelcomeFlowModel) {
        self.model = model
        _drawingViewModel = State(initialValue: model.drawingViewModel())
    }

    var body: some View {
        ZStack {
            if let landedDrawing {
                RootBrandedFrame {
                    landedStep(landedDrawing)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            } else {
                canvasScreen
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: landedDrawing != nil)
        // The drawing is saved on this phone and marked to send after sign-in.
        .onChange(of: drawingViewModel.delivery) { previous, delivery in
            guard previous == .sending, delivery == .waiting || delivery == .sent else {
                return
            }
            model.drawingSent()
            landedDrawing = drawingViewModel.widgetImage
            if landedDrawing == nil {
                model.finishDrawing()
            }
        }
    }

    private var canvasScreen: some View {
        NavigationStack {
            WidgetDrawingView(
                viewModel: drawingViewModel,
                title: .firstDayDrawingTitle,
                showsHistory: false,
                // Nothing can be sent or shared before there is an account.
                showsShareButton: false,
                showsSendStatus: false,
                emptyCanvasHint: .firstDayDrawingHint
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { model.back(onForgetInviteCode: {}) }) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text(.onboardingStartDateBackButton))
                    .accessibilityIdentifier("welcome.drawing.back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: model.skipDrawing) {
                        Text(.welcomeDrawingSkipButton)
                    }
                    .accessibilityIdentifier("welcome.drawing.skip")
                }
            }
        }
    }

    private func landedStep(_ drawing: UIImage) -> some View {
        OnboardingStepScaffold(
            title: .welcomeDrawingLandedTitle,
            message: .welcomeDrawingLandedMessage,
            primary: OnboardingStepAction(title: .authOnboardingCompleteButton, action: model.finishDrawing)
        ) {
            WidgetHomeScreenMock(drawing: drawing)
                .frame(maxWidth: 230)
        } content: {
            EmptyView()
        }
    }
}
