import SwiftUI

extension ThreadChatView {
    var pendingAnswer: ThreadChatProjection.PendingAnswer? {
        guard let question, let sendingAnswer, question.ownAnswerDetail == nil else { return nil }
        return ThreadChatProjection.PendingAnswer(instanceID: question.id, preview: sendingAnswer)
    }
}
