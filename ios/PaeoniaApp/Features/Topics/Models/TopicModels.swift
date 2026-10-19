import CryptoKit
import Foundation

/// One topic on the shelf, with its copy in the phone's language.
nonisolated struct TopicSummary: Identifiable, Equatable, Sendable {
    /// The topic key, such as `travel_and_places`.
    let id: String
    let title: String
    let subtitle: String
    let sortOrder: Int
    /// Flirt: kept off the lock screen and never named outside the topic.
    let isPrivate: Bool
    let totalCount: Int
    let togetherCount: Int
    let forYouCount: Int
    let waitingForPartnerCount: Int

    init(_ remote: RemoteTopicSummary, locale: Locale = .current) {
        let norwegian = locale.prefersNorwegianTopicCopy
        id = remote.topicKey
        title = norwegian ? remote.titleNB : remote.titleEN
        subtitle = norwegian ? remote.subtitleNB : remote.subtitleEN
        sortOrder = remote.sortOrder
        isPrivate = remote.isPrivate
        totalCount = remote.totalCount
        togetherCount = remote.togetherCount
        forYouCount = remote.forYouCount
        waitingForPartnerCount = remote.waitingForPartnerCount
    }

    /// Every question the couple kept has answers from both of them.
    var isFinished: Bool {
        totalCount > 0 && togetherCount >= totalCount
    }

    /// How much of the topic the couple has answered together, from 0 to 1.
    var progress: Double {
        totalCount > 0 ? min(Double(togetherCount) / Double(totalCount), 1) : 0
    }
}

/// Where one question stands for this person. The topic screen groups by it.
nonisolated enum TopicQuestionState: Equatable, Sendable {
    /// The partner answered it and this person hasn't.
    case forYou
    /// Nobody has answered it.
    case upNext
    /// This person answered it (or it is sending) and the partner hasn't.
    case waitingForPartner
    /// Both answered, so both answers and the chat are open.
    case together
    /// The couple put it aside.
    case skipped
}

/// One question of a topic as the app shows it.
nonisolated struct TopicQuestionItem: Identifiable, Equatable, Sendable {
    /// The couple's instance of the question, or, before anyone answered, the one the
    /// app will start. Its id is `TopicInstanceID.make`, the same on both phones.
    let question: DailyChallengeQuestion
    let sortOrder: Int
    let isSkipped: Bool

    var id: UUID {
        question.id
    }

    /// `isSending` is true while this person's answer is saved on the phone and still
    /// on its way, so it already counts as answered.
    func state(isSending: Bool) -> TopicQuestionState {
        if isSkipped {
            return .skipped
        }
        let ownAnswered = question.hasOwnAnswer || isSending
        if ownAnswered {
            return question.hasPartnerAnswer ? .together : .waitingForPartner
        }
        return question.hasPartnerAnswer ? .forYou : .upNext
    }
}

/// A topic's questions grouped the way its screen lists them, each group in the
/// topic's own order.
nonisolated struct TopicSections: Equatable, Sendable {
    var forYou: [TopicQuestionItem] = []
    var upNext: [TopicQuestionItem] = []
    var waitingForPartner: [TopicQuestionItem] = []
    var together: [TopicQuestionItem] = []
    var skipped: [TopicQuestionItem] = []

    init(items: [TopicQuestionItem], isSending: (UUID) -> Bool) {
        let ordered = items.sorted {
            ($0.sortOrder, $0.question.questionKey) < ($1.sortOrder, $1.question.questionKey)
        }
        for item in ordered {
            switch item.state(isSending: isSending(item.id)) {
            case .forYou: forYou.append(item)
            case .upNext: upNext.append(item)
            case .waitingForPartner: waitingForPartner.append(item)
            case .together: together.append(item)
            case .skipped: skipped.append(item)
            }
        }
    }

    /// What "Answer the next one" opens: a question the partner already answered
    /// first, then the next one nobody has started.
    var nextToAnswer: TopicQuestionItem? {
        forYou.first ?? upNext.first
    }

    /// The next question to answer after `id`, for the answer flow's Next button.
    func next(after id: UUID) -> TopicQuestionItem? {
        (forYou + upNext).first { $0.id != id }
    }
}

/// The id of a couple's instance of a topic question. Both phones derive the same id
/// from the couple and the question, so a draft, a staged photo, or an answer still
/// sending keeps its id whoever answers first. The server starts the instance under
/// this id, or joins the one the partner started under it.
nonisolated enum TopicInstanceID {
    static func make(coupleID: UUID, questionID: UUID) -> UUID {
        let seed = "paeonia.topic-instance:\(coupleID.uuidString.lowercased()):\(questionID.uuidString.lowercased())"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        // A name-based (version 5 style) uuid with the RFC 4122 variant.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension TopicQuestionItem {
    /// Builds a topic's questions from the server rows. A started question uses the
    /// couple's instance with its answers. One nobody has answered gets a question
    /// this person can start, under the id both phones share.
    nonisolated static func items(
        from detail: RemoteTopicDetail,
        currentUserID: UUID,
        coupleID: UUID,
        locale: Locale = .current
    ) -> [TopicQuestionItem] {
        let topicKey = detail.topic.topicKey
        return detail.questions.map { remote in
            let started = remote.row.flatMap { row in
                DailyChallengeQuestion.list(
                    currentUserID: currentUserID,
                    rows: [row],
                    answerDetails: detail.answerDetails,
                    locale: locale
                ).first
            }
            var question = started ?? .unstartedTopicQuestion(
                remote,
                topicKey: topicKey,
                currentUserID: currentUserID,
                coupleID: coupleID,
                locale: locale
            )
            question.topicKey = topicKey
            return TopicQuestionItem(question: question, sortOrder: remote.sortOrder, isSkipped: remote.isSkipped)
        }
    }
}

extension DailyChallengeQuestion {
    /// A topic question nobody has answered yet, ready for this person to start. It
    /// has no day: topic questions don't end, so the day fields only fill the shape.
    nonisolated static func unstartedTopicQuestion(
        _ remote: RemoteTopicQuestionRow,
        topicKey: String,
        currentUserID: UUID,
        coupleID: UUID,
        locale: Locale
    ) -> DailyChallengeQuestion {
        let norwegian = locale.prefersNorwegianTopicCopy
        let id = TopicInstanceID.make(coupleID: coupleID, questionID: remote.questionID)
        return DailyChallengeQuestion(
            id: id,
            coupleDayID: id,
            coupleID: coupleID,
            localDate: "",
            effectiveLocalDate: "",
            startsAt: .distantPast,
            endsAt: .distantFuture,
            seededForUserID: currentUserID,
            slotNumber: 0,
            status: .active,
            questionID: remote.questionID,
            questionVersionID: remote.questionVersionID,
            questionKey: remote.questionKey,
            prompt: norwegian ? remote.promptNB : remote.promptEN,
            shortPrompt: norwegian ? remote.shortPromptNB : remote.shortPromptEN,
            answerKinds: remote.answerKinds,
            ownAnswer: nil,
            partnerAnswer: nil,
            canViewPartnerAnswer: false,
            ownAnswerDetail: nil,
            partnerAnswerDetail: nil,
            origin: .own,
            isCurrentDay: false,
            topicKey: topicKey,
            options: DailyAnswerOptions.make(
                en: (remote.optionAEN, remote.optionBEN),
                nb: (remote.optionANB, remote.optionBNB),
                locale: locale
            )
        )
    }
}
