import SwiftUI

/// The partner's avatar as one glass capsule, the way the Dynamic Island holds a notification. On its
/// own the capsule is as wide as the face, so it is a circle. A notice or the buttons stretch that
/// same glass toward the middle of the screen, and the face stays where it was at the `faceEdge` end.
/// A notice that wraps makes the glass taller than the face, toward the middle of the screen, and the
/// face stays in its row at the `faceRow` end.
/// The glass is the ring pill's background (`CallMorphPart.background`), so a call grows out of it.
struct PresenceIsland<Content: View, Face: View>: View {
    let faceEdge: HorizontalEdge
    /// `.bottom` when the glass grows up from the face's row, and `.top` when it grows down.
    let faceRow: VerticalAlignment
    let showsContent: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let face: Face

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: faceRow, spacing: 0) {
            if faceEdge == .leading { face }
            if showsContent {
                content
                    .transition(reduceMotion ? .opacity : contentTransition)
            }
            if faceEdge == .trailing { face }
        }
        .background {
            Color.clear
                .glassEffect(.regular.interactive(), in: Self.glass)
                .callMorph(.background)
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    /// A capsule while it is one row tall. Taller, its corners stay round around the face.
    private static var glass: RoundedRectangle {
        RoundedRectangle(cornerRadius: PresenceAvatar.outerSize.height / 2, style: .circular)
    }

    private var contentTransition: AnyTransition {
        AnyTransition(IslandReveal(faceEdge: faceEdge))
    }
}

/// Uncovers the content from the face's side at the pace the glass stretches over it, so no text
/// or button shows outside the glass on the way.
private struct IslandReveal: Transition {
    let faceEdge: HorizontalEdge

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .mask {
                IslandRevealShape(
                    progress: phase.isIdentity ? 1 : 0, faceEdge: faceEdge,
                    height: PresenceAvatar.outerSize.height)
            }
    }
}

/// The part of the content the glass covers `progress` of the way, with the glass's round end on
/// the side away from the face. Fully open it reaches past the content, so a badge that pokes out
/// of a button stays whole.
nonisolated private struct IslandRevealShape: Shape {
    var progress: CGFloat
    let faceEdge: HorizontalEdge
    /// The glass's height while it is one row tall, which also sets how round its end is.
    let height: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard progress < 1 else { return Path(rect.insetBy(dx: 0, dy: -rect.height)) }
        let width = rect.width * max(progress, 0)
        let shownHeight = max(rect.height, height)
        let shown = CGRect(
            x: faceEdge == .leading ? rect.minX : rect.maxX - width, y: rect.midY - shownHeight / 2,
            width: width, height: shownHeight)
        let radius = min(height, width) / 2
        let end = faceEdge == .leading
            ? UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius)
            : UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
        return end.path(in: shown)
    }
}

/// The partner's face with a small badge for where they are: the game's picture or a chat bubble.
/// Its photo is the one the ring pill and the call screen grow out of (`CallMorphPart`). The glass
/// around it is `PresenceIsland`'s.
struct PresenceAvatar: View {
    let participants: DailyChallengeParticipants
    let place: PresencePlace

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
        .overlay(alignment: .bottomTrailing) { PresencePlaceBadge(place: place) }
        // The photo's own frame, which the call's photo matches. The badge reaches past it and
        // scales with it, so it grows out of the call and back into it with the photo.
        .frame(width: Self.size, height: Self.size)
        .callMorph(.photo, size: Self.size)
        .padding(PaeoniaSpacing.space4)
    }
}

/// Where the partner is, as a small badge for the bottom trailing corner of their face: the game's
/// picture, a pencil for the drawing or a chat bubble. Nothing while they are elsewhere in the app.
/// The partner's avatar wears it, and the call's bubble while it covers the avatar.
struct PresencePlaceBadge: View {
    let place: PresencePlace

    private func symbolBadge(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(width: 20, height: 20)
            .background(.paeoniaSurfacePrimary, in: Circle())
            .accessibilityHidden(true)
    }

    var body: some View {
        switch place {
        case let .playing(kind):
            // The pictures are rectangles, so they get a size whose corners stay inside the circle.
            PaeoniaBannerGameIcon(kind: kind)
                .frame(width: 16, height: 16)
                .padding(PaeoniaSpacing.space4)
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

/// The count of the chats with something from the partner this person has not read, at the
/// avatar's top corner, or on Message while the buttons show. It stays after the notice about it
/// has gone.
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

/// What the partner just did, or the chat they type in, inside the avatar's capsule: a line that
/// says what or where, and one with the message or what a tap does. Each wraps instead of cutting
/// the words off. A tap opens the chat, the game or the screen it is about, unless `canOpen` is false.
struct PresenceCalloutContent: View {
    /// Keeps a notice to a readable width on an iPad. A phone has less room than this beside the face.
    static let textWidthCap: CGFloat = 360

    let callout: PresenceCallout
    let partnerName: String
    let canOpen: Bool
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two lines each, which fits every notification's words. A chat message can be longer, and the
    /// chat shows the rest. Large accessibility text gets more lines, because fewer words fit in one.
    private var lineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 6 : 2
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: PaeoniaSpacing.space8) {
                icon
                // As wide as the words, up to the room beside the face or the cap. A frame with a
                // largest width would always take all of it and stretch the capsule.
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
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
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

/// Where the partner is, then Call, Message, and Join while the partner is in a game or the drawing
/// that this person does not have open, as round buttons inside the avatar's capsule. The place
/// sits next to the face and puts its badge into words. The buttons are smaller than the face, so
/// they read as the avatar's own controls rather than things beside it.
struct PresenceActions: View {
    static let buttonSize: CGFloat = 32
    /// Leaves room for the face and three buttons on a 375 point wide phone.
    static let placeWidthCap: CGFloat = 120

    let partnerName: String
    let place: PresencePlace?
    /// The end of the capsule the face is at, which the place sits next to.
    let faceEdge: HorizontalEdge
    /// The chat Message opens (`PartnerPresenceModel.messageTarget`). Nil hides Message.
    let messageChat: ThreadChatSubject?
    let unreadChats: Int
    /// A game or the drawing.
    let join: PresenceDestination?
    let call: () -> Void
    let message: (ThreadChatSubject) -> Void
    let open: (PresenceDestination) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if faceEdge == .leading { placeCaption }
            PresenceActionButton(label: .callsCallPartner(partnerName), identifier: "presence.call", action: call) {
                Image(systemName: "phone.fill")
                    .accessibilityHidden(true)
            }
            if let messageChat {
                PresenceActionButton(
                    label: messageLabel(messageChat), identifier: "presence.message", badgeCount: unreadChats,
                    action: { message(messageChat) }
                ) {
                    Image(systemName: "bubble.left.fill")
                        .accessibilityHidden(true)
                }
                .accessibilityValue(
                    unreadChats > 0 ? Text(.presenceAvatarUnreadChats(unreadChats)) : Text(verbatim: ""))
            }
            joinButton
            if faceEdge == .trailing { placeCaption }
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
    }

    /// The avatar's own VoiceOver label already says where the partner is.
    @ViewBuilder
    private var placeCaption: some View {
        if let place, place != .here {
            WidthCap(Self.placeWidthCap) {
                Text(place.title)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, PaeoniaSpacing.space8)
            .accessibilityHidden(true)
        }
    }

    private func messageLabel(_ chat: ThreadChatSubject) -> LocalizedStringResource {
        switch chat {
        case let .game(game):
            .presenceToolbarMessageGameAccessibilityLabel(partnerName, String(localized: game.kind.name))
        case .question: .presenceToolbarMessageQuestionAccessibilityLabel(partnerName)
        case .memory: .presenceToolbarMessageMemoryAccessibilityLabel(partnerName)
        case .story: .presenceToolbarMessageStoryAccessibilityLabel(partnerName)
        case .couple: .presenceToolbarMessageAccessibilityLabel(partnerName)
        }
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
    var badgeCount = 0
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: PresenceActions.buttonSize, height: PresenceActions.buttonSize)
                .background(fill, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badgeCount > 0 {
                        PresenceUnreadBadge(count: badgeCount)
                            .offset(x: PaeoniaSpacing.space4, y: -PaeoniaSpacing.space4)
                            .transition(.paeoniaPop)
                    }
                }
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
    /// A symbol under the chevron for something that goes on while the window is tucked away, such
    /// as this phone sharing its screen during a call.
    var mark: String?

    init(edge: HorizontalEdge, partnerName: String, hasWaitingNotice: Bool) {
        self.init(
            edge: edge, label: Text(.presenceTabAccessibilityLabel(partnerName)), hasWaitingNotice: hasWaitingNotice)
    }

    /// A tab for something else tucked at the edge, such as the call's window of the partner's screen.
    init(
        edge: HorizontalEdge, label: Text, identifier: String = "presence.tab", hasWaitingNotice: Bool,
        mark: String? = nil
    ) {
        self.edge = edge
        self.label = label
        self.identifier = identifier
        self.hasWaitingNotice = hasWaitingNotice
        self.mark = mark
    }

    static let size = CGSize(width: 24, height: 56)

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: edge == .trailing ? "chevron.compact.left" : "chevron.compact.right")
                .font(.system(size: mark == nil ? 20 : 16, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
            if let mark {
                Image(systemName: mark)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.paeoniaError)
            }
        }
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
