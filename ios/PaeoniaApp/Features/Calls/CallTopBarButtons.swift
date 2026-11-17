import SwiftUI

/// Share your screen and Message, at the top right of the call screen while the call is under way.
/// Message sits in the corner, as on the partner's avatar, and Share sits left of it, so the row of
/// buttons at the bottom keeps room for five on the smallest phone. Share asks the system's picker,
/// and the call shares only once the person picks there. While the share starts the button spins and
/// takes no tap. While they share the button is white, and a tap stops it. While the partner shares,
/// a new share takes over and the partner's stops (`CallShareTurns`), so VoiceOver says so.
struct CallTopBarButtons: View {
    static let shareSymbol = "rectangle.inset.filled.and.person.filled"

    let session: CallSession
    let engine: any CallEngineActions
    let partnerName: String
    let canOpenChat: Bool
    let openChat: () -> Void

    private var takesOverPartnersShare: Bool {
        session.isPartnerSharingScreen && (session.screenShare == .off || session.screenShare == .failed)
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            shareButton

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

    private var shareButton: some View {
        Button {
            switch session.screenShare {
            case .on: engine.stopScreenShare()
            case .off, .failed: engine.startScreenShare()
            case .starting: break
            }
        } label: {
            ZStack {
                if session.screenShare == .starting {
                    ProgressView()
                        .tint(.paeoniaTextPrimary)
                } else {
                    Image(systemName: Self.shareSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(session.isSharingScreen
                            ? Color.paeoniaTextInverse : Color.paeoniaTextPrimary)
                        .contentTransition(.symbolEffect(.replace))
                        .callTurned()
                }
            }
        }
        .buttonStyle(PaeoniaGlassCircleButtonStyle(
            face: PaeoniaSpacing.compactButtonHeight,
            glass: session.isSharingScreen ? .regular.tint(.white) : .regular))
        .accessibilityLabel(Text(shareLabel))
        .accessibilityHint(
            takesOverPartnersShare ? Text(.callsShareScreenPartnerSharingHint(partnerName)) : Text(verbatim: ""))
        .accessibilityIdentifier("calls.shareScreen")
    }

    private var shareLabel: LocalizedStringResource {
        switch session.screenShare {
        case .on: .callsSharingStopAccessibilityLabel
        case .starting: .callsShareScreenStarting
        case .off, .failed: .callsShareScreen
        }
    }
}
