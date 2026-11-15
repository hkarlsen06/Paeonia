import SwiftUI

/// The phone button that calls the partner, in every game's toolbar, on Us and in "Just us". It
/// starts a voice call, after the night check. While a call is live it opens the call screen
/// instead. `label` draws the button and gets whether a call is live.
struct CallButton<LabelView: View>: View {
    @ViewBuilder let label: (_ isInCall: Bool) -> LabelView
    @Environment(CallStarter.self) private var starter: CallStarter?
    @Environment(\.threadChatContext) private var context

    private var isInCall: Bool { starter?.center.isInCall == true }
    private var partnerName: String { context.participants.partnerName }

    var body: some View {
        if let starter, context.isAvailable {
            Button {
                starter.start(partnerName: partnerName)
            } label: {
                label(isInCall)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isInCall ? .callsOpenCall : .callsCallPartner(partnerName)))
            .accessibilityIdentifier("calls.start")
        }
    }
}

extension CallButton where LabelView == CallButtonIcon {
    /// The round phone icon of the toolbars, which fills in green while a call is live.
    init() {
        label = { CallButtonIcon(isInCall: $0) }
    }
}

struct CallButtonIcon: View {
    let isInCall: Bool

    var body: some View {
        Image(systemName: isInCall ? "phone.fill" : "phone")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(isInCall ? .paeoniaPresence : .paeoniaTextPrimary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

/// "Call back" under a missed call in "Just us". It goes through the same start path as the
/// phone buttons, night check included.
struct CallBackButton: View {
    @Environment(CallStarter.self) private var starter: CallStarter?
    @Environment(\.threadChatContext) private var context

    var body: some View {
        if let starter, context.isAvailable {
            Button {
                starter.start(partnerName: context.participants.partnerName)
            } label: {
                Label {
                    Text(.callsCallBack)
                } icon: {
                    Image(systemName: "phone.fill")
                }
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityLabel(Text(.callsCallBackAccessibilityLabel(context.participants.partnerName)))
            .accessibilityIdentifier("calls.callBack")
        }
    }
}
