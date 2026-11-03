import SwiftUI

extension DailyChallengeScreen {
    var ordinaryConversations: [SubjectConversation] {
        conversations.filter {
            if case .game(let game) = $0.subject { return !partnerGameKinds.contains(game.kind) }
            return true
        }
    }

    var activeGameChats: some View {
        Group {
            if let coupleID, !partnerGameKinds.isEmpty {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    Text(.gamesConversationPartnerPlaying(viewModel.participants.partnerName))
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                    ForEach(partnerGameKinds.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                        activeGameChat(kind: kind, coupleID: coupleID)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activeGameChat(kind: GameKind, coupleID: UUID) -> some View {
        let subject = GameChatSubject(coupleID: coupleID, kind: kind)
        if let conversation = conversations.first(where: { $0.id == subject.id }) {
            SubjectConversationCard(conversation: conversation, people: storyPeople) {
                chatContext.openGameChat?(kind, nil, nil)
            }
        } else {
            Button {
                chatContext.openGameChat?(kind, nil, nil)
            } label: {
                PaeoniaCard {
                    HStack(spacing: PaeoniaSpacing.space12) {
                        GameChatThumbnail(kind: kind)
                            .frame(width: 56, height: 56)
                        Text(kind.name)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.activeGame.\(kind.rawValue)")
        }
    }
}
