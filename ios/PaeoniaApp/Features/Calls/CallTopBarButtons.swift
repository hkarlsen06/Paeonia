import SwiftUI

/// Share your screen and Message, at the top right of the call screen while the call is under way.
/// Message sits in the corner, as on the partner's avatar, and Share sits left of it, so the row of
/// buttons at the bottom keeps room for five on the smallest phone. Share asks the system's picker,
/// and the call shares only once the person picks there. While they share the button is white, and
/// a tap stops it.
struct CallTopBarButtons: View {
    let session: CallSession
    let engine: any CallEngineActions
    let canOpenChat: Bool
    let openChat: () -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Button {
                if session.isSharingScreen {
                    engine.stopScreenShare()
                } else {
                    engine.startScreenShare()
                }
            } label: {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(session.isSharingScreen ? Color.paeoniaTextInverse : Color.paeoniaTextPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .callTurned()
            }
            .buttonStyle(PaeoniaGlassCircleButtonStyle(
                face: PaeoniaSpacing.compactButtonHeight,
                glass: session.isSharingScreen ? .regular.tint(.white) : .regular))
            .accessibilityLabel(Text(session.isSharingScreen ? .callsSharingStopAccessibilityLabel : .callsShareScreen))
            .accessibilityIdentifier("calls.shareScreen")

            if canOpenChat {
                Button(action: openChat) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .callTurned()
                }
                .buttonStyle(PaeoniaGlassCircleButtonStyle(face: PaeoniaSpacing.compactButtonHeight))
                .accessibilityLabel(Text(.callsOpenChat))
                .accessibilityIdentifier("calls.openChat")
            }
        }
    }
}
