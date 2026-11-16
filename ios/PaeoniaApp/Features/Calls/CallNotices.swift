import SwiftUI

/// What the call says beside its video, newest worries first: that this person shares their screen
/// or that their share did not start, an offer to turn the camera off, a weak connection, and what
/// the partner just did (`CallCallout`). The full call screen shows it above its buttons and the
/// bubble beside itself.
struct CallNotices: View {
    let session: CallSession
    let engine: any CallEngineActions
    let partnerName: String
    let callout: PresenceCallout?
    let openCallout: (PresenceDestination) -> Void
    /// The side the stack lines up on, the bubble's side over the app.
    var alignment = HorizontalAlignment.center

    /// Whether any notice shows. An ended call shows none.
    static func showsAny(_ session: CallSession, callout: PresenceCallout?) -> Bool {
        if case .ended = session.phase { return false }
        return session.isSharingScreen || hasNews(session, callout: callout)
    }

    /// Whether a notice other than the share's own shows, which the bubble's tab marks while it is
    /// tucked away.
    static func hasNews(_ session: CallSession, callout: PresenceCallout?) -> Bool {
        if case .ended = session.phase { return false }
        return session.screenShare == .failed || cameraOffSuggestion(in: session) != nil
            || session.weakConnection != nil || callout != nil
    }

    /// The offer only makes sense while the camera is on.
    private static func cameraOffSuggestion(in session: CallSession) -> CallCameraOffSuggestion? {
        session.isCameraOn ? session.cameraOffSuggestion : nil
    }

    var body: some View {
        if Self.showsAny(session, callout: callout) {
            VStack(alignment: alignment, spacing: PaeoniaSpacing.space8) {
                if session.isSharingScreen {
                    CallSharingNotice(stop: engine.stopScreenShare)
                        .transition(Self.arrival)
                }
                if session.screenShare == .failed {
                    CallShareFailedLine()
                        .transition(Self.arrival)
                }
                if let suggestion = Self.cameraOffSuggestion(in: session) {
                    CallCameraOffNotice(
                        suggestion: suggestion, turnOff: { engine.setCameraOn(false) },
                        dismiss: engine.dismissCameraOffSuggestion)
                        .transition(Self.arrival)
                }
                if let side = session.weakConnection {
                    CallWeakConnectionLine(side: side, partnerName: partnerName)
                        .transition(Self.arrival)
                }
                if let callout {
                    CallCallout(callout: callout, partnerName: partnerName, open: openCallout)
                        .transition(Self.arrival)
                }
            }
        }
    }

    private static let arrival = AnyTransition.scale(scale: 0.6).combined(with: .opacity)
}

/// "You're sharing your screen", with Stop. iOS shows its own red sign as well, but that one is easy
/// to miss in the Dynamic Island.
private struct CallSharingNotice: View {
    let stop: () -> Void

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Image(systemName: "record.circle")
                .foregroundStyle(.paeoniaError)
                .accessibilityHidden(true)
            Text(.callsSharingScreen)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
            Button(action: stop) {
                Text(.callsSharingStop)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextInverse)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space4)
                    .background(.paeoniaTextPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.callsSharingStopAccessibilityLabel))
            .accessibilityIdentifier("calls.sharing.stop")
        }
        .padding(.leading, PaeoniaSpacing.space12)
        .padding(.trailing, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space8)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calls.sharing")
    }
}

/// Offers to turn the person's camera off while the battery is low or the phone runs hot. Video makes
/// both worse, and the voice can go on without it.
private struct CallCameraOffNotice: View {
    let suggestion: CallCameraOffSuggestion
    let turnOff: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Label {
                Text(text)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.paeoniaTextPrimary)
            }
            HStack(spacing: PaeoniaSpacing.space8) {
                Button(action: turnOff) {
                    Text(.callsCameraOffTurnOff)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextInverse)
                        .padding(.horizontal, PaeoniaSpacing.space12)
                        .padding(.vertical, PaeoniaSpacing.space4)
                        .background(.paeoniaTextPrimary, in: Capsule())
                }
                .accessibilityIdentifier("calls.cameraOff.turnOff")
                Button(action: dismiss) {
                    Text(.callsCameraOffNotNow)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .padding(.horizontal, PaeoniaSpacing.space12)
                        .padding(.vertical, PaeoniaSpacing.space4)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .accessibilityIdentifier("calls.cameraOff.notNow")
            }
            .buttonStyle(.plain)
        }
        .padding(PaeoniaSpacing.space12)
        .frame(width: 260, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: PaeoniaRadius.radius20))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calls.cameraOff")
    }

    private var text: LocalizedStringResource {
        switch suggestion {
        case .lowBattery: .callsCameraOffLowBattery
        case .hot: .callsCameraOffHot
        }
    }

    private var symbol: String {
        switch suggestion {
        case .lowBattery: "battery.25percent"
        case .hot: "thermometer.high"
        }
    }
}

/// A small plain line while the connection is weak, so a blurry or late picture has a reason.
private struct CallWeakConnectionLine: View {
    let side: CallWeakSide
    let partnerName: String

    var body: some View {
        Label {
            Text(side == .mine ? .callsWeakConnectionMine : .callsWeakConnectionPartner(partnerName))
        } icon: {
            Image(systemName: "wifi.exclamationmark")
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .fixedSize()
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calls.weakConnection")
    }
}

/// The share did not start, such as when the system's picker could not show or the screen could not
/// be captured. It goes away after a few seconds, or at the next tap on Share.
private struct CallShareFailedLine: View {
    var body: some View {
        Label {
            Text(.callsSharingFailed)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space8)
        .fixedSize()
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calls.sharing.failed")
    }
}
