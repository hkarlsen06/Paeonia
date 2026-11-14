import SwiftUI

/// A call's quiet row in the middle of "Just us": "Missed call" with its time and Call back when
/// the partner called and nobody answered, "No answer" for the person's own call, and
/// "Call · 12 min" for one that was answered. It has no reply, edit, reaction or report actions.
struct ThreadChatCallRow: View {
    let message: ThreadChatMessage
    let isOwn: Bool

    private var call: ThreadChatCall? { message.call }
    private var isMissedFromPartner: Bool { call?.outcome == .missed && !isOwn }

    var body: some View {
        if let call {
            VStack(spacing: PaeoniaSpacing.space8) {
                HStack(spacing: PaeoniaSpacing.space4) {
                    Image(systemName: icon(for: call))
                        .foregroundStyle(isMissedFromPartner ? Color.paeoniaAccentPrimary : .paeoniaTextSecondary)
                        .accessibilityHidden(true)
                    Text(verbatim: call.title(isFromCurrentUser: isOwn))
                        .foregroundStyle(isMissedFromPartner ? Color.paeoniaTextPrimary : .paeoniaTextSecondary)
                    Text(verbatim: "·")
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.paeoniaTextTertiary)
                }
                .font(PaeoniaTypography.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                if isMissedFromPartner {
                    CallBackButton()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space12)
            .accessibilityIdentifier("chat.callRow")
        }
    }

    private func icon(for call: ThreadChatCall) -> String {
        switch call.outcome {
        case .missed: isOwn ? "phone.arrow.up.right" : "phone.arrow.down.left"
        case .completed: "phone.fill"
        }
    }
}
