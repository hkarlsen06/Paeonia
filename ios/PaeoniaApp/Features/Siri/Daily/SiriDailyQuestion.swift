import AppIntents
import Foundation

@available(iOS 27.3, *)
struct SiriDailyQuestion: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "siri.daily.question")
    static let defaultQuery = SiriDailyQuestionQuery()
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    let id: UUID
    @Property(title: "siri.daily.prompt", authenticationPolicy: .requiresLocalDeviceAuthentication)
    var prompt: String

    var displayRepresentation: DisplayRepresentation { .init(title: "\(prompt)") }

    init(_ question: DailyChallengeQuestion) {
        id = question.id
        prompt = question.prompt
    }

    struct SiriDailyQuestionQuery: EntityQuery {
        @MainActor
        func entities(for identifiers: [UUID]) async throws -> [SiriDailyQuestion] {
            // Parameter resolution never substitutes a different day's question.
            let access = await SiriAppContext.shared.access()
            guard let couple = access.coupleForEntityQuery(appIsLocked: AppLockModel.shared.isLocked) else {
                return []
            }
            let model = await SiriDailyQuestions.load(for: couple)
            let refreshedAccess = await SiriAppContext.shared.access()
            guard refreshedAccess.coupleForEntityQuery(appIsLocked: AppLockModel.shared.isLocked) == couple,
                  let question = model.snapshot.todayQuestion,
                  identifiers.contains(question.id), question.coupleID == couple.coupleID,
                  question.startsAt <= Date(), question.endsAt > Date()
            else { return [] }
            return [SiriDailyQuestion(question)]
        }
    }
}

@MainActor
enum SiriDailyQuestions {
    static func load(for couple: SiriCouple) async -> DailyChallengeViewModel {
        let model = SiriAppContext.shared.dailyChallengeModel()
        if model.currentUserID != couple.ownerUserID {
            await model.configure(currentUserID: couple.ownerUserID)
        }
        await model.reload()
        return model
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
struct ReadTodayQuestionIntent: AppIntent {
    static let title = LocalizedStringResource(
        "siri.daily.read", table: "Localizable", comment: "Siri daily question action."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "siri.daily.read.description", table: "Localizable", comment: "Siri daily question action guidance."
    ))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SiriDailyQuestion> {
        let couple = try await coupleToActFor()
        let model = await SiriDailyQuestions.load(for: couple)
        guard try await coupleToActFor() == couple,
              let question = model.snapshot.todayQuestion,
              question.coupleID == couple.coupleID,
              question.startsAt <= model.now(), question.endsAt > model.now()
        else { throw SiriFailure(.siriDailyUnavailable) }
        return .result(value: SiriDailyQuestion(question))
    }
}

@available(iOS 27.3, *)
@AppIntent(.tool)
struct AnswerTodayQuestionIntent: AppIntent {
    static let title = LocalizedStringResource(
        "siri.daily.answer", table: "Localizable", comment: "Siri daily question action."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "siri.daily.answer.description", table: "Localizable", comment: "Siri daily question action guidance."
    ))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @Parameter(title: "siri.daily.question") var question: SiriDailyQuestion
    @Parameter(title: "siri.daily.text") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let couple = try await coupleToActFor()
        let model = await SiriDailyQuestions.load(for: couple)
        guard try await coupleToActFor() == couple else { throw SiriFailure(.siriAccessSignedOut) }
        try await model.submitSiriText(text, instanceID: question.id, couple: couple) {
            let current = try await coupleToActFor()
            return current == couple
        }
        guard try await coupleToActFor() == couple else { throw SiriFailure(.siriAccessSignedOut) }
        await SiriAppContext.shared.syncAfterLocalChange()
        guard try await coupleToActFor() == couple else { throw SiriFailure(.siriAccessSignedOut) }
        return .result(dialog: IntentDialog(.siriDailySaved))
    }
}
