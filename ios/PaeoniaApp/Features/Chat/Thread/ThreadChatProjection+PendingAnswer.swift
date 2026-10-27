import Foundation

extension ThreadChatProjection {
    static func waiting(in round: DailyChatRound, input: Input) -> DailyChatRound.Waiting? {
        guard input.pendingAnswer?.instanceID == round.instanceID,
              !round.answers.contains(where: \.isOwnAnswer)
        else { return round.waiting }
        if round.waiting == .yourAnswer { return .reveal }
        return round.waiting ?? .partner
    }

    static func pendingAnswerRow(in round: DailyChatRound, input: Input, after date: Date?) -> ThreadChatRow? {
        guard let pending = input.pendingAnswer, pending.instanceID == round.instanceID,
              !round.answers.contains(where: \.isOwnAnswer)
        else { return nil }
        return ThreadChatRow(
            id: pendingAnswerRowPrefix + round.instanceID.uuidString,
            kind: .pendingAnswer(pending.preview),
            isCurrentUser: true,
            createdAt: (date ?? round.startsAt).addingTimeInterval(0.001),
            groupContext: .standalone(isCurrentUser: true),
            status: nil,
            quotedPreview: nil
        )
    }
}
