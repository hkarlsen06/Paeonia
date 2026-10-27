#if DEBUG
import Foundation

/// Launch arguments select production composer states without a server or personal data.
nonisolated enum DeveloperDailyComposerFixture {
    static func question(format: String, dayID: UUID) -> DailyChallengeQuestion? {
        let kinds: [DailyChallengeAnswerKind]
        let prompt: String
        switch format {
        case "photo", "photo-text":
            kinds = format == "photo" ? [.photo] : [.photo, .text]
            prompt = "Show or describe what you can see from where you are sitting right now."
        case "voice", "voice-text":
            kinds = format == "voice" ? [.voice] : [.voice, .text]
            prompt = "What everyday sound from your partner do you miss hearing, like their laugh, keys or humming?"
        case "partner", "partner-text":
            kinds = format == "partner" ? [.partnerChoice] : [.partnerChoice, .text]
            prompt = """
                Who is most likely to remember what makes a visit go smoothly,
                like tickets, food or a plan for the first evening?
                """
        case "either", "either-text":
            kinds = format == "either" ? [.eitherOr] : [.eitherOr, .text]
            prompt = "Would you rather go on a road trip without a plan or spend a week in one cosy cabin?"
        case "text":
            kinds = [.text]
            prompt = "What is one small moment from today that made you think of your partner?"
        default:
            return nil
        }
        var question = previewDailyQuestion(
            coupleDayID: dayID, prompt: prompt, short: "A moment together", answerKinds: kinds
        )
        if kinds.contains(.eitherOr) {
            question.options = DailyAnswerOptions(first: "Road trip", second: "A cosy cabin")
        }
        return question
    }
}
#endif
