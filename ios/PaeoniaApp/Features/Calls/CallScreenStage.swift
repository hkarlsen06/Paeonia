import SwiftUI

/// The call screen's videos (`CallStageView`) over the whole window, or small above the chat panel,
/// where a tap on them closes the chat (`CallChatPreview`). It reports the window's whole height,
/// which the chat panel takes its share of.
struct CallScreenStage: View {
    let engine: any CallEngineActions
    let session: CallSession
    let stage: CallStage
    let participants: DailyChallengeParticipants
    let isChatMounted: Bool
    let isChatRaised: Bool
    /// The previews keep out of the controls' room. While the controls are hidden they move into it.
    let makesRoomForControls: Bool
    /// From the bottom of the safe area to the top of the controls' stack.
    let controlsHeight: CGFloat
    /// The window's safe area, measured outside the stage.
    let safeArea: EdgeInsets
    let turn: CallTurn
    @Binding var corner: CallPreviewCorner
    let bringForward: (CallVideoSource) -> Void
    let closeChat: () -> Void
    let heightChanged: (CGFloat) -> Void

    private static let chatPreviewRadius = PaeoniaRadius.radius28

    var body: some View {
        GeometryReader { proxy in
            let insets = safeArea
            let window = CGRect(origin: .zero, size: proxy.size)
            let preview = chatPreviewFrame(in: window, insets: insets)
            ZStack {
                CallStageView(
                    engine: engine, session: session, stage: stage, partnerName: participants.partnerName,
                    frame: isChatRaised ? preview : window, margins: previewMargins(insets),
                    safeArea: isChatRaised ? EdgeInsets() : insets,
                    turn: turn, showsPreviews: !isChatRaised,
                    cornerRadius: isChatRaised ? Self.chatPreviewRadius : 0,
                    corner: $corner, bringForward: bringForward)
                if isChatMounted {
                    CallChatPreview(
                        session: session, participants: participants, showsIdentity: isChatRaised && stage.main == nil,
                        close: closeChat)
                        .frame(width: preview.width, height: preview.height)
                        .position(x: preview.midX, y: preview.midY)
                }
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: heightChanged)
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

    /// Above the chat panel, under the status bar.
    private func chatPreviewFrame(in window: CGRect, insets: EdgeInsets) -> CGRect {
        let gap = PaeoniaSpacing.space8
        let top = insets.top + gap
        let bottom = window.height - window.height * CallChatPanel.heightFraction - gap
        return CGRect(
            x: insets.leading + gap, y: top, width: max(0, window.width - insets.leading - insets.trailing - 2 * gap),
            height: max(0, bottom - top))
    }
}
