import Foundation

extension RemoteSearchResponse {
    /// The server's matches as results. A chat the app has no screen for is left out.
    var results: [SearchResult] {
        let questionResults = self.questions.map { question in
            SearchResult(
                kind: .question,
                key: question.questionID,
                title: question.prompt,
                label: question.topicTitle,
                date: MemoryTimeline.parseLocalDate(question.localDate),
                dateIsCalendarDay: true,
                destination: .question(question.questionID)
            )
        }
        let answerResults = self.answers.map { answer in
            SearchResult(
                kind: .answer,
                key: answer.answerID,
                title: answer.snippet,
                detail: answer.prompt,
                label: answer.topicTitle,
                authorUserID: answer.authorUserID,
                date: answer.answeredAt,
                destination: .question(answer.questionID)
            )
        }
        let messageResults = self.messages.compactMap { message -> SearchResult? in
            let destination: SearchDestination
            switch (message.threadKind, message.questionID, message.memoryID, message.storyID) {
            case let ("daily_question", questionID?, _, _):
                destination = .question(questionID)
            case let ("memory", _, memoryID?, _):
                destination = .memoryComments(memoryID)
            case let ("story", _, _, storyID?):
                destination = .storyReplies(storyID)
            default:
                return nil
            }
            return SearchResult(
                kind: .message,
                key: message.messageID,
                title: message.snippet,
                detail: message.contextTitle,
                label: message.topicTitle,
                authorUserID: message.senderUserID,
                date: message.createdAt,
                destination: destination
            )
        }
        let storyResults = self.storyChain.map { story in
            SearchResult(
                kind: .storyChain,
                key: story.storyID,
                title: story.title ?? story.snippet,
                detail: story.title == nil ? nil : story.snippet,
                date: story.finishedAt,
                destination: .storyChain(story.storyID)
            )
        }
        return questionResults + answerResults + messageResults + storyResults
    }
}
