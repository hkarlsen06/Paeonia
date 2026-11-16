import SwiftUI

/// The partner's avatar as one glass capsule, the way the Dynamic Island holds a notification. On its
/// own it is the round face in its own glass, which grows out of a call with its photo. A notice or
/// the buttons widen it toward the middle of the screen into one capsule of glass, and the face stays
/// where it was at the `faceEdge` end.
struct PresenceIsland<Content: View, Face: View>: View {
    let faceEdge: HorizontalEdge
    let showsContent: Bool
    @ViewBuilder let content: Content
    /// Draws its own glass only while `showsContent` is false.
    @ViewBuilder let face: Face

    var body: some View {
        HStack(spacing: 0) {
            if faceEdge == .leading { face }
            if showsContent { content }
            if faceEdge == .trailing { face }
        }
        .background {
            // One glass for the whole capsule. Glass laid over glass looks muddy, so the face's own
            // gives way while this one is there.
            if showsContent {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

/// The partner's face with a small badge for where they are: the game's picture or a chat bubble.
/// Its photo is the one the ring pill and the call screen grow out of (`CallMorphPart`).
struct PresenceAvatar: View {
    let participants: DailyChallengeParticipants
    let place: PresencePlace
    /// Off while the capsule's glass is behind the face.
    var hasOwnGlass = true

    static let size: CGFloat = 44
    /// The face with the glass around it, which is what sits at the edge.
    static let outerSize = CGSize(width: size + 2 * PaeoniaSpacing.space4, height: size + 2 * PaeoniaSpacing.space4)

    var body: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: participants.partnerProfilePhotoAssetID,
            name: participants.partnerName,
            tint: .paeoniaPartnerTwo,
            size: Self.size
        )
        .padding(PaeoniaSpacing.space4)
        .overlay(alignment: .bottomTrailing) { badge }
        .glassEffect(hasOwnGlass ? .regular.interactive() : .identity, in: Circle())
        // The photo's own frame, which the call's photo matches. The glass and the badge reach
        // past it and scale with it, so the whole avatar grows out of the call and back into it.
        .frame(width: Self.size, height: Self.size)
        .callMorph(.photo, size: Self.size)
        .padding(PaeoniaSpacing.space4)
    }

    private func symbolBadge(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(width: 20, height: 20)
            .background(.paeoniaSurfacePrimary, in: Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var badge: some View {
        switch place {
        case let .playing(kind):
            PaeoniaBannerGameIcon(kind: kind)
                .frame(width: 20, height: 20)
                .padding(PaeoniaSpacing.space2)
                .background(.paeoniaSurfacePrimary, in: Circle())
        case .drawing:
            symbolBadge("pencil")
        case .chatting:
            symbolBadge("bubble.left.fill")
        case .here:
            EmptyView()
        }
    }
}

/// The count at the avatar's top corner of the chats with something from the partner this person
/// has not read. It stays after the notice about it has gone.
struct PresenceUnreadBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 9 ? "9+" : "\(count)")
            .font(PaeoniaTypography.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, PaeoniaSpacing.space4)
            .frame(minWidth: 20, minHeight: 20)
            .background(.red, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What the partner just did, or the chat they type in, inside the avatar's capsule: one line that
/// says what or where, and one with the message or what a tap does. A tap opens the chat, the game
/// or the screen it is about, unless `canOpen` is false.
struct PresenceCalloutContent: View {
    static let textWidthCap: CGFloat = 220

    let callout: PresenceCallout
    let partnerName: String
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: PaeoniaSpacing.space8) {
                icon
                // As wide as the words, up to the cap. A frame with a largest width would always
                // take all of it and stretch the capsule.
                WidthCap(PresenceCalloutContent.textWidthCap) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: callout.title)
                            .font(PaeoniaTypography.caption.weight(.semibold))
                            .foregroundStyle(.paeoniaTextSecondary)
                        if let detail = callout.detail(partnerName: partnerName) {
                            Text(verbatim: detail)
                                .font(PaeoniaTypography.body)
                                .foregroundStyle(.paeoniaTextPrimary)
                        }
                    }
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.space12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: callout.accessibilityLabel(partnerName: partnerName)))
        .accessibilityHint(canOpen ? Text(hint) : Text(verbatim: ""))
        .accessibilityAddTraits(canOpen ? .isButton : [])
        .accessibilityIdentifier("presence.notice")
    }

    private var hint: LocalizedStringResource {
        if case .chat = callout.destination { return .presenceNoticeOpenChatAccessibilityHint }
        return .presenceNoticeOpenAccessibilityHint
    }

    @ViewBuilder
    private var icon: some View {
        switch callout {
        case let .openedGame(kind), let .game(kind, _):
            PaeoniaBannerGameIcon(kind: kind)
                .frame(width: 28, height: 28)
        case .openedDrawing:
            PaeoniaDeepLinkIcon(link: .widgetDrawing)
                .frame(width: 28, height: 28)
        case .typing:
            GameTypingDots()
        case .message:
            EmptyView()
        case let .update(update):
            if let link = update.deepLink {
                PaeoniaDeepLinkIcon(link: link)
                    .frame(width: 28, height: 28)
            }
        }
    }
}

/// Call, Message, and Join while the partner is in a game or the drawing that this person does not
/// have open, as round buttons inside the avatar's capsule. They are smaller than the face, so they
/// read as the avatar's own controls rather than things beside it.
struct PresenceActions: View {
    static let buttonSize: CGFloat = 32

    let partnerName: String
    /// The chat Message opens, the game's own chat in a game. Nil hides Message while that chat is
    /// already on screen.
    let messageChat: ThreadChatSubject?
    /// A game or the drawing.
    let join: PresenceDestination?
    let call: () -> Void
    let message: () -> Void
    let open: (PresenceDestination) -> Void

    var body: some View {
        HStack(spacing: 0) {
            PresenceActionButton(label: .callsCallPartner(partnerName), identifier: "presence.call", action: call) {
                Image(systemName: "phone.fill")
                    .accessibilityHidden(true)
            }
            if let messageChat {
                PresenceActionButton(
                    label: messageLabel(messageChat), identifier: "presence.message", action: message
                ) {
                    Image(systemName: "bubble.left.fill")
                        .accessibilityHidden(true)
                }
            }
            joinButton
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
    }

    private func messageLabel(_ chat: ThreadChatSubject) -> LocalizedStringResource {
        if case let .game(game) = chat {
            return .presenceToolbarMessageGameAccessibilityLabel(partnerName, String(localized: game.kind.name))
        }
        return .presenceToolbarMessageAccessibilityLabel(partnerName)
    }

    @ViewBuilder
    private var joinButton: some View {
        switch join {
        case let .game(kind):
            PresenceActionButton(
                label: .presenceToolbarJoinAccessibilityLabel(String(localized: kind.name)),
                identifier: "presence.join", fill: .paeoniaPresence, action: { open(.game(kind)) }
            ) {
                PaeoniaBannerGameIcon(kind: kind)
                    .frame(width: 22, height: 22)
            }
        case .drawing:
            PresenceActionButton(
                label: .presenceToolbarJoinDrawingAccessibilityLabel(partnerName),
                identifier: "presence.join", fill: .paeoniaPresence, action: { open(.drawing) }
            ) {
                Image(systemName: "pencil")
                    .accessibilityHidden(true)
            }
        case .chat, .link, nil:
            EmptyView()
        }
    }
}

private struct PresenceActionButton<Icon: View>: View {
    let label: LocalizedStringResource
    let identifier: String
    var fill: Color = .white.opacity(0.12)
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: PresenceActions.buttonSize, height: PresenceActions.buttonSize)
                .background(fill, in: Circle())
                // The touch target stays the size of the capsule's height.
                .frame(
                    width: PresenceActions.buttonSize + PaeoniaSpacing.space8, height: PresenceAvatar.outerSize.height)
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
    /// What VoiceOver calls the tab, the partner's avatar's by default.
    let label: Text
    var identifier = "presence.tab"
    let hasWaitingNotice: Bool

    init(edge: HorizontalEdge, partnerName: String, hasWaitingNotice: Bool) {
        self.init(
            edge: edge, label: Text(.presenceTabAccessibilityLabel(partnerName)), hasWaitingNotice: hasWaitingNotice)
    }

    /// A tab for something else tucked at the edge, such as the call's window of the partner's screen.
    init(edge: HorizontalEdge, label: Text, identifier: String = "presence.tab", hasWaitingNotice: Bool) {
        self.edge = edge
        self.label = label
        self.identifier = identifier
        self.hasWaitingNotice = hasWaitingNotice
    }

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
            .accessibilityLabel(label)
            .accessibilityValue(hasWaitingNotice ? Text(.presenceTabNewNotice) : Text(verbatim: ""))
            .accessibilityIdentifier(identifier)
    }

    /// Rounded on the side that faces the screen, flat against the edge.
    private var shape: UnevenRoundedRectangle {
        let radius = PaeoniaRadius.radius12
        return edge == .trailing
            ? UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
            : UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius)
    }
}

/// Lays its content out no wider than `width`, and as narrow as the content wants below it.
private struct WidthCap: Layout {
    let width: CGFloat

    init(_ width: CGFloat) {
        self.width = width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let capped = ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)
        return subviews.first?.sizeThatFits(capped) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
