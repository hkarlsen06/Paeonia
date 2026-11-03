import SwiftUI

/// Opens the game's chat through the root. On a game screen it opens as a sheet over the game.
struct GameConversationButton: View {
    let kind: GameKind
    var source: GameConversationSource?
    var result: GameConversationResult?

    @Environment(\.threadChatContext) private var context

    init(source: GameConversationSource, result: GameConversationResult? = nil) {
        kind = source.kind
        self.source = source
        self.result = result
    }

    init(kind: GameKind) {
        self.kind = kind
    }

    private var resolvedTitle: LocalizedStringResource {
        guard let coupleID = context.coupleID else { return .gamesConversationOpen }
        return context.summaries?.summary(for: .game(GameChatSubject(coupleID: coupleID, kind: kind))) == nil
            ? .gamesConversationStart : .gamesConversationOpen
    }

    private var hasUnreadMessage: Bool {
        guard let coupleID = context.coupleID else { return false }
        return context.summaries?.isUnread(.game(GameChatSubject(coupleID: coupleID, kind: kind))) == true
    }

    var body: some View {
        if context.isAvailable, context.openGameChat != nil {
            button
        }
    }

    private var button: some View {
        Button { context.openGameChat?(kind, source, result) } label: {
            Label { Text(resolvedTitle) } icon: { Image(systemName: "bubble.left.and.bubble.right") }
                .labelStyle(.iconOnly)
        }
        // A toolbar shows only the label's symbol, so drawing on it never appears. An empty badge is a dot.
        .badge(hasUnreadMessage ? Text(verbatim: "") : nil)
        .accessibilityLabel(
            Text(hasUnreadMessage ? .dailyChatCardUnreadTitle(context.participants.partnerName) : resolvedTitle)
        )
        .accessibilityIdentifier("game.conversation.open")
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
