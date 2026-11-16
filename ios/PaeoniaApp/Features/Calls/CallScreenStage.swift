import SwiftUI

/// The call screen's videos (`CallStageView`) over the whole window, with room left for the
/// chevron's row and the controls.
struct CallScreenStage: View {
    let engine: any CallEngineActions
    let session: CallSession
    let stage: CallStage
    let partnerName: String
    /// The previews keep out of the controls' room. While the controls are hidden they move into it.
    let makesRoomForControls: Bool
    /// From the bottom of the safe area to the top of the controls' stack.
    let controlsHeight: CGFloat
    /// The window's safe area, measured outside the stage.
    let safeArea: EdgeInsets
    let turn: CallTurn
    @Binding var corner: CallPreviewCorner
    let bringForward: (CallVideoSource) -> Void

    var body: some View {
        GeometryReader { proxy in
            CallStageView(
                engine: engine, session: session, stage: stage, partnerName: partnerName,
                frame: CGRect(origin: .zero, size: proxy.size), margins: previewMargins(safeArea),
                safeArea: safeArea, turn: turn, corner: $corner, bringForward: bringForward)
        }
        .ignoresSafeArea()
    }

    /// The room the previews leave for the chevron's row and the controls, on screen.
    private func previewMargins(_ insets: EdgeInsets) -> EdgeInsets {
        let roomy = makesRoomForControls
        let controls = controlsHeight + PaeoniaSpacing.space24
        let topBar = PaeoniaSpacing.compactButtonHeight + PaeoniaSpacing.space16
        return EdgeInsets(
            top: insets.top + (roomy ? topBar : PaeoniaSpacing.space8),
            leading: insets.leading + PaeoniaSpacing.screenHorizontalPadding,
            bottom: insets.bottom + (roomy ? controls + PaeoniaSpacing.space16 : PaeoniaSpacing.space24),
            trailing: insets.trailing + PaeoniaSpacing.screenHorizontalPadding
        )
    }
}
