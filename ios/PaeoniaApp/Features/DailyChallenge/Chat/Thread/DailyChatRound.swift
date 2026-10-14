import Foundation

/// One day a question came up, as the chat page draws it: the question, the answers
/// the user may read, and what the day is still waiting for. A couple has one chat per
/// question, so the page stacks every day of that question, oldest first.
nonisolated struct DailyChatRound: Equatable {
    /// What a day is waiting for, shown as a short note under its answers.
    enum Waiting: Equatable {
        /// The partner hasn't answered, and no day of the question has both answers yet.
        case partnerBeforeChat
        /// The partner hasn't answered this day. The chat is already open from an earlier day.
        case partner
        /// The partner has answered. The user's own answer to this day is still to come.
        case yourAnswer
        /// The user's answer is saved. The partner's opens once it has been sent.
        case reveal
    }

    let instanceID: UUID
    let prompt: String
    let startsAt: Date
    /// The answers the user may read, oldest first. The partner's shows only once it is revealed.
    let answers: [DailyQuestionAnswerDetail]
    /// The partner has opened the page since the user's answer showed for them.
    let ownAnswerSeenByPartner: Bool
    let waiting: Waiting?
    /// How two partner-choice picks line up, once the user can read both.
    let match: PartnerChoiceMatch?
    /// The match plays its small celebration, because this day was just revealed.
    var celebratesMatch = false
    /// Whether a media answer on this day is a photo or a voice recording. A question that
    /// comes back can take another kind, so each day keeps its own.
    var mediaKind: DailyChallengeAnswerKind = .photo
}

extension DailyChatRound {
    /// `chatIsOpen` says whether some day of the question already has both answers.
    init(
        question: DailyChallengeQuestion,
        participants: DailyChallengeParticipants,
        chatIsOpen: Bool,
        celebratesMatch: Bool = false
    ) {
        let partnerAnswer = question.partnerAnswerDetail.flatMap { $0.canViewAnswer ? $0 : nil }
        let waiting: Waiting?
        if !question.hasPartnerAnswer {
            waiting = question.hasOwnAnswer ? (chatIsOpen ? .partner : .partnerBeforeChat) : nil
        } else if !question.hasOwnAnswer {
            waiting = .yourAnswer
        } else {
            waiting = partnerAnswer == nil ? .reveal : nil
        }
        let match = question.partnerChoiceMatch(participants: participants)
        self.init(
            instanceID: question.id,
            prompt: question.prompt,
            startsAt: question.startsAt,
            answers: [question.ownAnswerDetail, partnerAnswer]
                .compactMap(\.self)
                .sorted { $0.answeredAt < $1.answeredAt },
            ownAnswerSeenByPartner: question.ownAnswerSeenByPartnerAt != nil,
            waiting: waiting,
            match: match,
            celebratesMatch: celebratesMatch && match != nil,
            mediaKind: question.mediaAnswerKind
        )
    }
}

nonisolated enum DailyChatRounds {
    /// The question's days for the page, oldest first. `loaded` is what the server last
    /// sent, nil before any read, and `entry` is the day the user opened the page from.
    ///
    /// The server decides which days exist and what the user may read, so a day or a partner
    /// answer the server no longer sends goes away. Two things come from `entry`. Before
    /// the server has answered in this visit (`serverConfirmed` is false), the opened day
    /// shows even if the list on this phone lacks it, so the page opens complete. And the
    /// user's own answer shows on its day if the server's copy does not have it yet.
    static func merged(
        loaded: [DailyChallengeQuestion]?,
        entry: DailyChallengeQuestion,
        serverConfirmed: Bool
    ) -> [DailyChallengeQuestion] {
        guard var rounds = loaded else { return [entry] }
        if let index = rounds.firstIndex(where: { $0.id == entry.id }) {
            if !rounds[index].hasOwnAnswer, entry.hasOwnAnswer {
                rounds[index].ownAnswer = entry.ownAnswer
                rounds[index].ownAnswerDetail = entry.ownAnswerDetail
            }
        } else if !serverConfirmed {
            rounds.append(entry)
        }
        return rounds.sorted {
            if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// The question's chat can be used once any of its days has both answers readable.
    static func isChatAvailable(_ rounds: [DailyChallengeQuestion]) -> Bool {
        rounds.contains(where: \.isChatAvailable)
    }

    /// Where the page first scrolls.
    enum OpeningScroll: Equatable {
        /// The newest message, at the bottom.
        case newestMessage
        /// The top of the list, where the oldest day starts.
        case oldestRow
        /// The start of one day, given by its instance id.
        case questionRow(UUID)
    }

    /// The page opens on `focusing`'s day, or on the newest day when that is nil or no
    /// longer there. On the newest day, people who have written since it started find
    /// the page at their newest message. Any other opening starts at the day's question.
    static func openingScroll(
        rounds: [DailyChallengeQuestion],
        focusing instanceID: UUID?,
        messages: [DailyQuestionChatMessage]
    ) -> OpeningScroll {
        guard let target = rounds.first(where: { $0.id == instanceID }) ?? rounds.last else { return .newestMessage }
        if target.id == rounds.last?.id {
            let start = [target.ownAnswer?.answeredAt, target.partnerAnswer?.answeredAt].compactMap(\.self).min()
                ?? target.startsAt
            if messages.contains(where: { $0.createdAt >= start }) { return .newestMessage }
        }
        return target.id == rounds.first?.id ? .oldestRow : .questionRow(target.id)
    }
}
