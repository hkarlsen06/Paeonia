import SwiftUI

/// Opens the shared chat. Its first message creates the thread through the normal outbox.
struct GameConversationButton: View {
    let source: GameConversationSource
    var result: GameConversationResult?
    var compact = false

    @Environment(\.threadChatContext) private var context
    @State private var chat: ThreadChatViewModel?
    @State private var isOpening = false

    private var title: LocalizedStringResource {
        context.summaries?.summary(for: .game(source)) == nil ? .gamesConversationStart : .gamesConversationOpen
    }

    var body: some View {
        if context.isAvailable {
            if compact {
                button.buttonStyle(.plain)
            } else {
                button.buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: isOpening))
            }
        }
    }

    private var button: some View {
        Button {
            guard !isOpening else { return }
            isOpening = true
            Task {
                chat = await context.makeViewModel(subject: .game(source), header: .game(source, result: result))
                isOpening = false
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .labelStyle(GameConversationLabelStyle(compact: compact))
        }
        .disabled(isOpening)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("game.conversation.open")
        .navigationDestination(
            isPresented: Binding(
                get: { chat != nil },
                set: { if !$0 { chat = nil } }
            )
        ) {
            if let chat {
                ThreadChatScreen(viewModel: chat)
            }
        }
    }
}

private struct GameConversationLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        if compact { configuration.icon } else { Label(configuration).labelStyle(.titleAndIcon) }
    }
}

extension View {
    func gameConversationToolbar(_ source: GameConversationSource?, result: GameConversationResult? = nil) -> some View
    {
        toolbar {
            if let source {
                ToolbarItem(placement: .topBarTrailing) {
                    GameConversationButton(source: source, result: result, compact: true)
                }
            }
        }
    }
}

extension ThreadChatHeader {
    static func game(_ source: GameConversationSource, result: GameConversationResult? = nil) -> Self {
        Self(
            eyebrow: String(localized: .gamesConversationGame),
            title: String(localized: source.kind.name),
            detail: result?.date.formatted(.dateTime.day().month(.abbreviated)),
            photoAssetID: nil,
            gameSource: source,
            gameResult: result
        )
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
