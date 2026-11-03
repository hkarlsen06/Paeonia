#if DEBUG
    import SwiftUI

    struct DeveloperGameChatPreviews: View {
        private let dependencies = DeveloperGamesScenarioFactory.dependencies(for: .exquisiteCorpseReveal)

        private var context: ThreadChatContext {
            var context = ThreadChatContext()
            context.participants.currentUserID = DeveloperGamesFixture.me
            context.gameDrawings = GameHistoryDrawings(
                store: dependencies.drawingStore, transfer: dependencies.drawingTransfer)
            context.gamePreview = { kind in
                switch kind {
                case .connectFour: return .board(.init(kind: kind, moves: [0, 1, 0, 1, 0, 1, 0], me: .one))
                case .dotsAndBoxes:
                    return .board(.init(kind: kind, moves: [0, 20, 4, 21, 1, 22, 5, 25, 9, 26], me: .one))
                default:
                    return await GameChatPreviewLoader(dependencies: dependencies).load(
                        for: kind, userID: DeveloperGamesFixture.me)
                }
            }
            return context
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        ForEach([GameKind.connectFour, .exquisiteCorpse, .dotsAndBoxes], id: \.self) { kind in
                            SubjectConversationCard(
                                conversation: conversation(kind),
                                people: .init(currentName: "Alex", partnerName: "Robin")
                            ) {}
                        }
                    }
                    .padding(PaeoniaSpacing.screenHorizontalPadding)
                }
                .navigationTitle(Text(.mainTabQuestions))
                .navigationBarTitleDisplayMode(.inline)
                .paeoniaScreenBackground()
            }
            .environment(\.threadChatContext, context)
        }

        private func conversation(_ kind: GameKind) -> SubjectConversation {
            let subject = GameChatSubject(coupleID: DeveloperScenarioFixture.coupleID, kind: kind)
            return SubjectConversation(
                subject: .game(subject),
                summary: ThreadChatSummary(
                    threadID: subject.id, coupleID: subject.coupleID, subject: .game(subject),
                    createdAt: .now, updatedAt: .now, lastMessageID: nil, lastMessageAt: nil,
                    lastMessageSenderUserID: nil, lastMessageBody: "Your move!"), isUnread: false)
        }
    }
#endif
