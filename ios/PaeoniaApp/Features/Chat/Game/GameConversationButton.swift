import SwiftUI

/// Opens the game's chat through the root. On a game screen it opens as a sheet over the game.
/// It also shows whether the partner is in that chat, and when they type, so a slow move has a reason.
struct GameConversationButton: View {
    let kind: GameKind
    var source: GameConversationSource?
    var result: GameConversationResult?

    @Environment(\.threadChatContext) private var context
    @State private var presence: ThreadChatPresenceModel?

    init(source: GameConversationSource, result: GameConversationResult? = nil) {
        kind = source.kind
        self.source = source
        self.result = result
    }

    init(kind: GameKind) {
        self.kind = kind
    }

    private var subject: ThreadChatSubject? {
        context.coupleID.map { .game(GameChatSubject(coupleID: $0, kind: kind)) }
    }

    private var resolvedTitle: LocalizedStringResource {
        guard let subject else { return .gamesConversationOpen }
        return context.summaries?.summary(for: subject) == nil ? .gamesConversationStart : .gamesConversationOpen
    }

    private var hasUnreadMessage: Bool {
        guard let subject else { return false }
        return context.summaries?.isUnread(subject) == true
    }

    private var partnerIsTyping: Bool { presence?.partnerIsTyping == true }
    private var partnerIsInChat: Bool { partnerIsTyping || presence?.partnerIsInChat == true }

    var body: some View {
        if context.isAvailable, context.openGameChat != nil {
            button
                .task(id: subject) { await followPartner() }
        }
    }

    /// A plain button with its own drawing, because a toolbar keeps only a label's symbol name and
    /// drops its effects. The fixed frame keeps the score beside it still when the state changes.
    private var button: some View {
        Button { context.openGameChat?(kind, source, result) } label: {
            icon
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(partnerIsInChat ? .paeoniaPresence : .paeoniaTextPrimary)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if hasUnreadMessage {
                        Circle()
                            .fill(.paeoniaAccentPrimary)
                            .frame(width: 9, height: 9)
                            .padding(PaeoniaSpacing.space4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(hasUnreadMessage ? .dailyChatCardUnreadTitle(context.participants.partnerName) : resolvedTitle)
        )
        .accessibilityValue(partnerStatus.map(Text.init) ?? Text(verbatim: ""))
        .accessibilityIdentifier("game.conversation.open")
    }

    /// The bubbles fill while the partner has the chat open, and become typing dots while they write.
    private var icon: some View {
        Image(systemName: partnerIsTyping ? "ellipsis.bubble.fill"
            : partnerIsInChat ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            .symbolEffect(
                .variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous), isActive: partnerIsTyping)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
            .animation(.default, value: partnerIsTyping)
            .animation(.default, value: partnerIsInChat)
    }

    private var partnerStatus: LocalizedStringResource? {
        let name = context.participants.partnerName
        if partnerIsTyping { return .dailyChatTyping(name) }
        return partnerIsInChat ? .gamesConversationPartnerInChat(name) : nil
    }

    /// Follows the partner's typing and open chat while the button is on screen.
    private func followPartner() async {
        guard let subject, let coupleID = context.coupleID, let service = context.service else { return }
        let model = ThreadChatPresenceModel(coupleID: coupleID, subject: subject, service: service)
        presence = model
        await model.observe()
    }
}

extension View {
    func gameConversationToolbar(_ source: GameConversationSource?, result: GameConversationResult? = nil)
        -> some View
    {
        toolbar {
            if let source {
                ToolbarItem(placement: .topBarTrailing) {
                    GameConversationButton(source: source, result: result)
                }
            }
        }
    }
}

extension ThreadChatHeader {
    static func game(_ subject: GameChatSubject) -> Self {
        Self(eyebrow: String(localized: .gamesConversationGame), title: String(localized: subject.kind.name),
             detail: nil, photoAssetID: nil, gameSubject: subject)
    }
}

nonisolated struct GameConversationRequest: Encodable {
    let coupleID: UUID
    let source: GameConversationSource
    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
        case source = "p_source"
    }
}
