import SwiftUI

/// The inviter's first drawing for their partner's Home Screen, on the same drawing
/// screen they'll use every day. Send saves it on this phone, shows it on their own
/// widget and sends it to the first day draft. Then, if the widget isn't on their Home
/// Screen yet, it walks them through adding it. Shown as a full-screen cover from the
/// invite screen.
struct FirstDayDrawingFlow: View {
    let model: InviterFirstDayModel
    let onClose: () -> Void

    @State private var drawingViewModel: WidgetDrawingViewModel
    /// The sent drawing, once the widget step should show it.
    @State private var nudgeDrawing: UIImage?
    @State private var isFinishingSend = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: InviterFirstDayModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _drawingViewModel = State(initialValue: model.makeDrawingViewModel())
    }

    var body: some View {
        ZStack {
            if let nudgeDrawing {
                WidgetNudgeStep(drawing: nudgeDrawing, authorName: model.authorName, placement: .standalone) { _ in
                    onClose()
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            } else {
                NavigationStack {
                    WidgetDrawingView(
                        viewModel: drawingViewModel,
                        title: .firstDayDrawingTitle,
                        showsHistory: false,
                        emptyCanvasHint: .firstDayDrawingHint
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                            }
                            .disabled(isFinishingSend)
                            .accessibilityLabel(Text(.commonClose))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.meaningfulMoment, value: nudgeDrawing != nil)
        .onChange(of: drawingViewModel.delivery) { previous, delivery in
            guard previous == .sending, delivery == .sent || delivery == .waiting else {
                return
            }
            finishSend(isWaiting: delivery == .waiting)
        }
    }

    /// The canvas shows "Sent" with its haptic first, then the flow moves on.
    private func finishSend(isWaiting: Bool) {
        guard !isFinishingSend else {
            return
        }
        isFinishingSend = true
        if isWaiting {
            bannerCenter.show(.info(message: String(localized: .firstDayDrawingWaitingMessage)))
        }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            if let image = await model.drawingSent() {
                nudgeDrawing = image
            } else {
                onClose()
            }
        }
    }
}
