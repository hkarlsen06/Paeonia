import SwiftUI

/// The partner's face with a small badge for where they are: the game's picture or a chat bubble.
/// Its photo is the one the ring pill and the call screen grow out of (`CallMorphPart`).
struct PresenceAvatar: View {
    let participants: DailyChallengeParticipants
    let place: PresencePlace

    static let size: CGFloat = 44
    /// The avatar with its glass ring, which is what sits in the corner.
    static let outerSize = CGSize(width: size + 2 * PaeoniaSpacing.space4, height: size + 2 * PaeoniaSpacing.space4)

    var body: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: participants.partnerProfilePhotoAssetID,
            name: participants.partnerName,
            tint: .paeoniaPartnerTwo,
            size: Self.size
        )
        .callMorph(.photo, size: Self.size)
        .padding(PaeoniaSpacing.space4)
        .glassEffect(.regular.interactive(), in: Circle())
        .overlay(alignment: .bottomTrailing) { badge }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    @ViewBuilder
    private var badge: some View {
        switch place {
        case let .playing(kind):
            PaeoniaBannerGameIcon(kind: kind)
                .frame(width: 20, height: 20)
                .padding(PaeoniaSpacing.space2)
                .background(.paeoniaSurfacePrimary, in: Circle())
        case .chatting:
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: 20, height: 20)
                .background(.paeoniaSurfacePrimary, in: Circle())
                .accessibilityHidden(true)
        case .here:
            EmptyView()
        }
    }
}

/// What the partner just did, or the chat they type in, beside the avatar. A tap opens the chat
/// or the game, unless `canOpen` is false.
struct PresenceNoticePill: View {
    let callout: PresenceCallout
    let partnerName: String
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: PaeoniaSpacing.space8) {
                switch callout {
                case let .openedGame(kind):
                    PaeoniaBannerGameIcon(kind: kind)
                        .frame(width: 28, height: 28)
                case .typing:
                    GameTypingDots()
                case .message:
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(callout.title)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(1)
                    if let detail {
                        Text(verbatim: detail)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextPrimary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)
            }
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: PaeoniaRadius.radius20))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(canOpen ? Text(.presenceNoticeOpenChatAccessibilityHint) : Text(verbatim: ""))
        .accessibilityAddTraits(canOpen ? .isButton : [])
        .accessibilityIdentifier("presence.notice")
    }

    private var detail: String? {
        switch callout {
        case let .message(message): message.preview
        case .openedGame: canOpen ? String(localized: .presenceNoticeJoin) : nil
        case .typing: nil
        }
    }

    private var accessibilityLabel: LocalizedStringResource {
        if case let .message(message) = callout {
            return .presenceNoticeMessageAccessibilityLabel(partnerName, message.preview)
        }
        return callout.title
    }
}

/// The toolbar the avatar opens: the partner's name and where they are, then Call, Message, and
/// Join while the partner is in a game this person does not have open. Without `showsButtons` it
/// has only the name and the place.
struct PresenceToolbar: View {
    let partnerName: String
    let headline: LocalizedStringResource
    let showsButtons: Bool
    /// Hidden while "Just us" is already on screen.
    let showsMessage: Bool
    let joinableGame: GameKind?
    let call: () -> Void
    let message: () -> Void
    let join: (GameKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(verbatim: partnerName)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(headline)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            if showsButtons { buttons }
        }
        .padding(PaeoniaSpacing.space12)
        .glassEffect(.regular, in: .rect(cornerRadius: PaeoniaRadius.radius20))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    /// In a row, or under one another when large text leaves no room for the row.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaeoniaSpacing.space12) { buttonList }
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) { buttonList }
        }
    }

    @ViewBuilder
    private var buttonList: some View {
        PresenceToolbarButton(
            title: .presenceToolbarCall, label: .callsCallPartner(partnerName), identifier: "presence.call",
            action: call
        ) {
            Image(systemName: "phone.fill")
                .accessibilityHidden(true)
        }
        if showsMessage {
            PresenceToolbarButton(
                title: .presenceToolbarMessage, label: .presenceToolbarMessageAccessibilityLabel(partnerName),
                identifier: "presence.message", action: message
            ) {
                Image(systemName: "bubble.left.fill")
                    .accessibilityHidden(true)
            }
        }
        if let joinableGame {
            PresenceToolbarButton(
                title: .presenceToolbarJoin,
                label: .presenceToolbarJoinAccessibilityLabel(String(localized: joinableGame.name)),
                identifier: "presence.join", fill: .paeoniaPresence, action: { join(joinableGame) }
            ) {
                PaeoniaBannerGameIcon(kind: joinableGame)
                    .frame(width: 28, height: 28)
            }
        }
    }
}

private struct PresenceToolbarButton<Icon: View>: View {
    let title: LocalizedStringResource
    let label: LocalizedStringResource
    let identifier: String
    var fill: Color = .white.opacity(0.12)
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: PaeoniaSpacing.space4) {
                icon
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.paeoniaTextPrimary)
                    .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                    .background(fill, in: Circle())
                Text(title)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// What sticks out at the edge while the avatar is tucked away: a chevron that points back in, and a
/// dot while a notice waits for it to come back.
struct PresenceTab: View {
    let edge: HorizontalEdge
    let partnerName: String
    let hasWaitingNotice: Bool

    static let size = CGSize(width: 24, height: 56)

    var body: some View {
        Image(systemName: edge == .trailing ? "chevron.compact.left" : "chevron.compact.right")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(width: Self.size.width, height: Self.size.height)
            .glassEffect(.regular.interactive(), in: shape)
            .overlay(alignment: edge == .trailing ? .topLeading : .topTrailing) {
                if hasWaitingNotice {
                    Circle()
                        .fill(.paeoniaAccentPrimary)
                        .frame(width: 10, height: 10)
                        .offset(x: edge == .trailing ? -3 : 3, y: -3)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.presenceTabAccessibilityLabel(partnerName)))
            .accessibilityValue(hasWaitingNotice ? Text(.presenceTabNewNotice) : Text(verbatim: ""))
            .accessibilityIdentifier("presence.tab")
    }

    /// Rounded on the side that faces the screen, flat against the edge.
    private var shape: UnevenRoundedRectangle {
        let radius = PaeoniaRadius.radius12
        return edge == .trailing
            ? UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
            : UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius)
    }
}
