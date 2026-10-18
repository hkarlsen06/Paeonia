import Foundation
import Testing
@testable import PaeoniaApp

struct DailyAnswerOptionsTests {
    private let options = DailyAnswerOptions(first: "By the sea", second: "In the mountains")

    private func detail(option: DailyAnswerOption?, own: Bool, canView: Bool = true) -> DailyQuestionAnswerDetail {
        DailyQuestionAnswerDetail(
            answerUserID: own ? TestDailyChallengeIDs.currentUser : TestDailyChallengeIDs.partnerUser,
            answerID: UUID(),
            answeredAt: Date(),
            isOwnAnswer: own,
            canViewAnswer: canView,
            textBody: nil,
            selectedUserID: nil,
            mediaAssetIDs: [],
            selectedOption: option
        ).labelingPick(with: options)
    }

    @Test func optionsFollowThePhonesLanguage() {
        let en = ("By the sea", "In the mountains")
        let nb = ("Ved sjøen", "På fjellet")
        #expect(DailyAnswerOptions.make(en: en, nb: nb, locale: Locale(identifier: "en"))?.first == "By the sea")
        #expect(DailyAnswerOptions.make(en: en, nb: nb, locale: Locale(identifier: "nb_NO"))?.second == "På fjellet")
        #expect(DailyAnswerOptions.make(en: (nil, nil), nb: (nil, nil), locale: Locale(identifier: "en")) == nil)
    }

    @Test func aDetailCarriesItsPickedLabel() {
        #expect(detail(option: .second, own: true).selectedOptionLabel == "In the mountains")
        #expect(detail(option: nil, own: true).selectedOptionLabel == nil)
    }

    @Test func thePickTravelsInTheRequestBody() throws {
        let body = DailyAnswerPayloadBody(
            answerID: UUID(),
            payload: DailyAnswerPayload(text: "Waves", optionChoice: .first)
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        )
        #expect(json["option_choice"] as? String == "a")
        #expect(json["text"] as? String == "Waves")
        #expect(json["partner_choice_user_id"] == nil)
    }

    @Test func aRefusedPickGoesBackIntoTheDraft() {
        let content = DailySubmitAnswerOperationPayload.Content.textAndOptionChoice("Waves", .second)
        #expect(content.restoredDraft == DailyAnswerDraft(text: "Waves", optionChoice: .second))
    }

    @Test func theWhyLineIsShort() {
        let question = DailyChallengeQuestion.unstartedTopicQuestion(
            RemoteTopicQuestionRow(
                questionID: UUID(),
                questionKey: "travel_sea_or_mountains",
                questionVersionID: UUID(),
                sortOrder: 3,
                promptEN: "Sea or mountains?",
                shortPromptEN: "Sea or mountains",
                promptNB: "Sjø eller fjell?",
                shortPromptNB: "Sjø eller fjell",
                answerKinds: [.eitherOr, .text],
                isSkipped: false,
                row: nil,
                optionAEN: "By the sea",
                optionBEN: "In the mountains",
                optionANB: "Ved sjøen",
                optionBNB: "På fjellet"
            ),
            topicKey: "travel_and_places",
            currentUserID: TestDailyChallengeIDs.currentUser,
            coupleID: TestDailyChallengeIDs.couple,
            locale: Locale(identifier: "en")
        )
        #expect(question.maxAnswerTextLength == DailyAnswerDraft.maxWhyLineLength)
        #expect(question.combinedSecondaryKind == .eitherOr)
        #expect(question.options?.first == "By the sea")
    }
}

struct PickMatchTests {
    private let options = DailyAnswerOptions(first: "By the sea", second: "In the mountains")

    private func question(own: DailyAnswerOption, partner: DailyAnswerOption) -> DailyChallengeQuestion {
        let ownDetail = DailyQuestionAnswerDetail(
            answerUserID: TestDailyChallengeIDs.currentUser, answerID: UUID(), answeredAt: Date(),
            isOwnAnswer: true, canViewAnswer: true, textBody: nil, selectedUserID: nil, mediaAssetIDs: [],
            selectedOption: own
        ).labelingPick(with: options)
        let partnerDetail = DailyQuestionAnswerDetail(
            answerUserID: TestDailyChallengeIDs.partnerUser, answerID: UUID(), answeredAt: Date(),
            isOwnAnswer: false, canViewAnswer: true, textBody: nil, selectedUserID: nil, mediaAssetIDs: [],
            selectedOption: partner
        ).labelingPick(with: options)
        return DailyChallengeQuestion(
            id: UUID(), coupleDayID: UUID(), coupleID: TestDailyChallengeIDs.couple, localDate: "",
            effectiveLocalDate: "", startsAt: Date(), endsAt: Date(),
            seededForUserID: TestDailyChallengeIDs.currentUser,
            slotNumber: 0, status: .answered, questionID: UUID(), questionVersionID: UUID(), questionKey: "wyr",
            prompt: "Sea or mountains?", shortPrompt: "Sea or mountains", answerKinds: [.eitherOr, .text],
            ownAnswer: DailyQuestionAnswerSummary(id: ownDetail.answerID, answeredAt: Date()),
            partnerAnswer: DailyQuestionAnswerSummary(id: partnerDetail.answerID, answeredAt: Date()),
            canViewPartnerAnswer: true, ownAnswerDetail: ownDetail, partnerAnswerDetail: partnerDetail,
            origin: .own, isCurrentDay: false, options: options
        )
    }

    @Test func samePicksCelebrate() {
        let match = question(own: .first, partner: .first).partnerChoiceMatch(participants: .init())
        #expect(match == .bothPickedOption("By the sea"))
        #expect(match?.isSamePick == true)
    }

    @Test func personPicksShowTheNamesPicked() {
        func picks(_ match: PartnerChoiceMatch) -> [String] {
            let picks = match.picks(viewerName: "Hjalmar", partnerName: "Elena")
            return [picks.yours, picks.theirs]
        }
        #expect(picks(.bothPickedPartner) == ["Elena", "Elena"])
        #expect(picks(.bothPickedViewer) == ["Hjalmar", "Hjalmar"])
        #expect(picks(.eachPickedTheOther) == ["Elena", "Hjalmar"])
        #expect(picks(.eachPickedThemselves) == ["Hjalmar", "Elena"])
    }

    @Test func differentPicksSayWhoPickedWhat() {
        let match = question(own: .first, partner: .second).partnerChoiceMatch(participants: .init())
        #expect(match == .pickedDifferentOptions(yours: "By the sea", theirs: "In the mountains"))
        #expect(match?.isSamePick == false)
    }
}
