import Foundation

nonisolated enum DailyChallengeAnswerKind: Codable, Equatable, Hashable, Identifiable, Sendable {
    case text
    case photo
    case voice
    case partnerChoice
    case unknown(String)

    var id: String { rawValue }

    init(rawValue: String) {
        switch rawValue {
        case "text":
            self = .text
        case "photo":
            self = .photo
        case "voice":
            self = .voice
        case "partner_choice":
            self = .partnerChoice
        default:
            self = .unknown(rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .text:
            "text"
        case .photo:
            "photo"
        case .voice:
            "voice"
        case .partnerChoice:
            "partner_choice"
        case let .unknown(value):
            value
        }
    }

    var supportsInlineTextSubmission: Bool {
        self == .text
    }
}

extension DailyChallengeAnswerKind {
    /// Short label for the kind-picker pill on multi-kind questions.
    var composerTitle: LocalizedStringResource {
        switch self {
        case .text, .unknown:
            .dailyChallengeKindText
        case .photo:
            .dailyChallengeKindPhoto
        case .voice:
            .dailyChallengeKindVoice
        case .partnerChoice:
            .dailyChallengeKindChoice
        }
    }

    var composerIcon: String {
        switch self {
        case .text, .unknown:
            "text.alignleft"
        case .photo:
            "photo"
        case .voice:
            "mic"
        case .partnerChoice:
            "person.2"
        }
    }
}

/// A half-written daily answer kept on the device so a partly-finished reply isn't
/// lost when the answering screen is closed and reopened — or the app is relaunched.
///
/// Today this carries in-progress text. It is the single shape every answer kind
/// flows through, so it grows to hold a partner pick and staged photo/voice as
/// those kinds are added; the draft store is versioned so new fields persist
/// without disturbing older saved drafts.
nonisolated struct DailyAnswerDraft: Codable, Equatable, Sendable {
    var text: String
    /// The person picked for a partner-choice question (one of the two partners).
    var partnerChoiceUserID: UUID?
    /// Which kind the user is answering with, for questions that accept more than one
    /// (e.g. photo or text). nil means "use the question's default kind".
    var selectedKind: DailyChallengeAnswerKind?
    /// Describes a picked-but-not-yet-sent photo or voice note. The bytes live in the
    /// staged-media store keyed by the question instance.
    var media: DailyAnswerMediaDraft?

    init(
        text: String = "",
        partnerChoiceUserID: UUID? = nil,
        selectedKind: DailyChallengeAnswerKind? = nil,
        media: DailyAnswerMediaDraft? = nil
    ) {
        self.text = text
        self.partnerChoiceUserID = partnerChoiceUserID
        self.selectedKind = selectedKind
        self.media = media
    }

    /// Whether the draft holds anything worth keeping. The store drops a draft once
    /// this is false, which is how clearing a field removes it from disk. The
    /// selected kind alone is not content — it's just a preference.
    var hasContent: Bool {
        !text.isEmpty || partnerChoiceUserID != nil || media != nil
    }
}

/// Metadata for a picked-but-not-yet-sent media answer. Kept in the draft so the
/// composer can show it and the upload can describe it; the bytes themselves live in
/// the staged-media store.
nonisolated struct DailyAnswerMediaDraft: Codable, Equatable, Sendable {
    var purpose: DailyAnswerMediaPurpose
    var mimeType: String
    var fileExtension: String
    var width: Int?
    var height: Int?
    var durationMs: Int?
}

/// What the user is actually sending for one answer, resolved from the draft at
/// submit time. The backend's `submit_daily_answer` accepts text, a partner pick,
/// or media ids in a single payload; this enum is the seam the service maps to that
/// payload.
nonisolated enum DailyAnswerPayload: Equatable, Sendable {
    case text(String)
    case partnerChoice(UUID)
    case media([UUID])
}

/// The two people in the couple, used to label partner-choice answers — "you" for
/// the current user and the partner's name — both while picking and once an answer
/// is revealed.
nonisolated struct DailyChallengeParticipants: Equatable, Sendable {
    var currentUserID: UUID?
    var currentDisplayName: String?
    var currentProfilePhotoAssetID: UUID?
    var partnerUserID: UUID?
    var partnerDisplayName: String?
    var partnerProfilePhotoAssetID: UUID?

    init(
        currentUserID: UUID? = nil,
        currentDisplayName: String? = nil,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerUserID: UUID? = nil,
        partnerDisplayName: String? = nil,
        partnerProfilePhotoAssetID: UUID? = nil
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerUserID = partnerUserID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
    }

    struct Option: Identifiable, Equatable, Sendable {
        let id: UUID
        /// Caption shown under the avatar — "You" for the current user, the
        /// partner's name otherwise.
        let label: String
        /// The person's real name, used for the avatar photo's accessibility label
        /// and the initials fallback when no photo is set.
        let avatarName: String
        let profilePhotoAssetID: UUID?
        let isCurrentUser: Bool
    }

    /// The two pickable people — "you" first, then the partner — or nil when the
    /// couple's identity isn't fully known yet, so the picker stays hidden.
    var partnerChoiceOptions: [Option]? {
        guard let currentUserID, let partnerUserID else { return nil }
        return [
            Option(
                id: currentUserID,
                label: String(localized: .dailyChallengeChoiceYou),
                avatarName: currentDisplayName ?? String(localized: .dailyChallengeChoiceYou),
                profilePhotoAssetID: currentProfilePhotoAssetID,
                isCurrentUser: true
            ),
            Option(
                id: partnerUserID,
                label: partnerName,
                avatarName: partnerName,
                profilePhotoAssetID: partnerProfilePhotoAssetID,
                isCurrentUser: false
            ),
        ]
    }

    /// How a chosen person reads inside a revealed answer.
    func name(for userID: UUID) -> String {
        if userID == currentUserID {
            return String(localized: .dailyChallengeChoiceYou)
        }
        return partnerName
    }

    private var partnerName: String {
        partnerDisplayName ?? String(localized: .dailyChallengeChoicePartnerFallback)
    }
}

nonisolated enum DailyQuestionInstanceStatus: Equatable, Sendable {
    case active
    case answered
    case shuffled
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "active":
            self = .active
        case "answered":
            self = .answered
        case "shuffled":
            self = .shuffled
        default:
            self = .unknown(rawValue)
        }
    }
}

nonisolated struct DailyQuestionAnswerSummary: Equatable, Sendable {
    let id: UUID
    let answeredAt: Date
}

nonisolated struct DailyQuestionAnswerDetail: Equatable, Sendable {
    let answerUserID: UUID
    let answerID: UUID
    let answeredAt: Date
    let isOwnAnswer: Bool
    let canViewAnswer: Bool
    let textBody: String?
    let selectedUserID: UUID?
    let mediaAssetIDs: [UUID]

    var hasMedia: Bool {
        !mediaAssetIDs.isEmpty
    }
}

nonisolated enum DailyQuestionOrigin: Equatable, Sendable {
    case own
    case partner
}

nonisolated struct DailyChallengeQuestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let coupleDayID: UUID
    let coupleID: UUID
    let localDate: String
    let startsAt: Date
    let endsAt: Date
    let seededForUserID: UUID
    let slotNumber: Int
    let status: DailyQuestionInstanceStatus
    let questionID: UUID
    let questionVersionID: UUID
    let questionKey: String
    let prompt: String
    let shortPrompt: String
    let answerKinds: [DailyChallengeAnswerKind]
    let ownAnswer: DailyQuestionAnswerSummary?
    let partnerAnswer: DailyQuestionAnswerSummary?
    let canViewPartnerAnswer: Bool
    let ownAnswerDetail: DailyQuestionAnswerDetail?
    let partnerAnswerDetail: DailyQuestionAnswerDetail?
    let origin: DailyQuestionOrigin

    var hasOwnAnswer: Bool {
        ownAnswer != nil
    }

    var hasPartnerAnswer: Bool {
        partnerAnswer != nil
    }

    var isVisibleToCurrentUser: Bool {
        origin == .own || hasPartnerAnswer || hasOwnAnswer
    }

    var isAvailableToAnswer: Bool {
        status != .shuffled && !hasOwnAnswer && (origin == .own || hasPartnerAnswer)
    }

    var supportsTextAnswer: Bool {
        answerKinds.contains(.text)
    }

    var supportsPartnerChoiceAnswer: Bool {
        answerKinds.contains(.partnerChoice)
    }

    var canSubmitTextAnswer: Bool {
        isAvailableToAnswer && supportsTextAnswer
    }

    /// Answer kinds the app can compose a reply for today.
    var composableAnswerKinds: [DailyChallengeAnswerKind] {
        answerKinds.filter { $0 == .text || $0 == .partnerChoice || $0 == .photo || $0 == .voice }
    }

    /// Which media kind a revealed media answer is. The reveal data only carries
    /// asset ids (no type), so we infer it from the question: a voice question reveals
    /// audio, anything else with media reveals a photo. This holds because no active
    /// question mixes photo and voice.
    var mediaAnswerKind: DailyChallengeAnswerKind {
        answerKinds.contains(.voice) ? .voice : .photo
    }

    /// The kind a question opens to when it accepts more than one. Text is preferred
    /// as the lowest-friction default; otherwise the first composable kind.
    var defaultComposableKind: DailyChallengeAnswerKind? {
        if composableAnswerKinds.contains(.text) {
            return .text
        }
        return composableAnswerKinds.first
    }

    var canSubmitAnswer: Bool {
        isAvailableToAnswer && defaultComposableKind != nil
    }

    /// The kind of a still-private own answer the user is allowed to change. Editing
    /// is allowed only while the answer is private — once the partner has answered the
    /// same instance the content is revealed and locked. Text and partner-choice
    /// answers can be changed; media answers cannot.
    var editableAnswerKind: DailyChallengeAnswerKind? {
        guard
            origin == .own,
            hasOwnAnswer,
            partnerAnswer == nil,
            status != .shuffled
        else { return nil }

        if supportsTextAnswer { return .text }
        if supportsPartnerChoiceAnswer { return .partnerChoice }
        return nil
    }

    /// Whether the user may still change their own answer (text or partner-choice).
    var canEditOwnAnswer: Bool {
        editableAnswerKind != nil
    }
}

nonisolated struct DailyChallengeProgress: Equatable, Sendable {
    static let requiredOwnQuestionCount = 3

    let ownQuestionCount: Int
    let ownAnsweredCount: Int
    let partnerQuestionCount: Int

    var requiredQuestionCount: Int {
        Self.requiredOwnQuestionCount
    }

    var isComplete: Bool {
        ownQuestionCount >= Self.requiredOwnQuestionCount
            && ownAnsweredCount >= Self.requiredOwnQuestionCount
    }
}

nonisolated struct DailyChallengeCardState: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case loading
        case noChallenge
        case active(prompt: String)
        case complete
    }

    let kind: Kind
    let answeredCount: Int
    let totalCount: Int

    var isActionEnabled: Bool {
        kind != .loading
    }
}

nonisolated struct DailyChallengeSnapshot: Equatable, Sendable {
    let currentUserID: UUID?
    let coupleDayID: UUID?
    let questions: [DailyChallengeQuestion]
    let refreshedAt: Date

    static func empty(currentUserID: UUID?, refreshedAt: Date = Date()) -> DailyChallengeSnapshot {
        DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: nil,
            questions: [],
            refreshedAt: refreshedAt
        )
    }

    var ownQuestions: [DailyChallengeQuestion] {
        questions
            .filter { $0.origin == .own }
            .sorted { $0.slotNumber < $1.slotNumber }
    }

    var partnerStartedQuestions: [DailyChallengeQuestion] {
        questions
            .filter { $0.origin == .partner && ($0.hasPartnerAnswer || $0.hasOwnAnswer) }
            .sorted {
                let lhsDate = $0.partnerAnswer?.answeredAt ?? $0.ownAnswer?.answeredAt ?? .distantPast
                let rhsDate = $1.partnerAnswer?.answeredAt ?? $1.ownAnswer?.answeredAt ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.slotNumber < $1.slotNumber
                }
                return lhsDate < rhsDate
            }
    }

    var visibleQuestions: [DailyChallengeQuestion] {
        (ownQuestions + partnerStartedQuestions).filter(\.isVisibleToCurrentUser)
    }

    /// Questions surfaced inside the focused answering flow, in the order the
    /// flow steps through them: the user's own three first, then any of the
    /// partner's questions the user can still answer. Already-answered own
    /// questions stay in the list so the user can swipe back and review them.
    var answerFlowQuestions: [DailyChallengeQuestion] {
        ownQuestions + partnerStartedQuestions.filter(\.isAvailableToAnswer)
    }

    var progress: DailyChallengeProgress {
        DailyChallengeProgress(
            ownQuestionCount: ownQuestions.count,
            ownAnsweredCount: ownQuestions.filter(\.hasOwnAnswer).count,
            partnerQuestionCount: partnerStartedQuestions.count
        )
    }

    var hasAnyQuestions: Bool {
        !visibleQuestions.isEmpty
    }

    var homeCardState: DailyChallengeCardState {
        if !hasAnyQuestions {
            return DailyChallengeCardState(
                kind: .noChallenge,
                answeredCount: progress.ownAnsweredCount,
                totalCount: progress.requiredQuestionCount
            )
        }

        if progress.isComplete {
            return DailyChallengeCardState(
                kind: .complete,
                answeredCount: progress.ownAnsweredCount,
                totalCount: progress.requiredQuestionCount
            )
        }

        let prompt = ownQuestions.first(where: { !$0.hasOwnAnswer })?.shortPrompt
            ?? partnerStartedQuestions.first(where: { !$0.hasOwnAnswer })?.shortPrompt
            ?? visibleQuestions.first?.shortPrompt
            ?? visibleQuestions.first?.prompt
            ?? ""

        return DailyChallengeCardState(
            kind: .active(prompt: prompt),
            answeredCount: progress.ownAnsweredCount,
            totalCount: progress.requiredQuestionCount
        )
    }

    static func make(
        currentUserID: UUID,
        rows: [DailyQuestionRow],
        answerDetails: [DailyAnswerDetailRow],
        locale: Locale = .current,
        refreshedAt: Date = Date()
    ) -> DailyChallengeSnapshot {
        let detailsByAnswerID = Dictionary(
            uniqueKeysWithValues: answerDetails.map { row in
                (row.answerID, row.detail)
            }
        )

        let questions = rows
            .filter { DailyQuestionInstanceStatus(rawValue: $0.instanceStatus) != .shuffled }
            .map { row in
                let ownAnswer = row.ownAnswerID.map {
                    DailyQuestionAnswerSummary(
                        id: $0,
                        answeredAt: row.ownAnsweredAt ?? row.startsAt
                    )
                }
                let partnerAnswer = row.partnerAnswerID.map {
                    DailyQuestionAnswerSummary(
                        id: $0,
                        answeredAt: row.partnerAnsweredAt ?? row.startsAt
                    )
                }

                return DailyChallengeQuestion(
                    id: row.instanceID,
                    coupleDayID: row.coupleDayID,
                    coupleID: row.coupleID,
                    localDate: row.localDate,
                    startsAt: row.startsAt,
                    endsAt: row.endsAt,
                    seededForUserID: row.seededForUserID,
                    slotNumber: Int(row.slotNumber),
                    status: DailyQuestionInstanceStatus(rawValue: row.instanceStatus),
                    questionID: row.questionID,
                    questionVersionID: row.questionVersionID,
                    questionKey: row.questionKey,
                    prompt: row.prompt(for: locale),
                    shortPrompt: row.shortPrompt(for: locale),
                    answerKinds: row.answerKinds,
                    ownAnswer: ownAnswer,
                    partnerAnswer: partnerAnswer,
                    canViewPartnerAnswer: row.canViewPartnerAnswer,
                    ownAnswerDetail: row.ownAnswerID.flatMap { detailsByAnswerID[$0] },
                    partnerAnswerDetail: row.partnerAnswerID.flatMap { detailsByAnswerID[$0] },
                    origin: row.seededForUserID == currentUserID ? .own : .partner
                )
            }
            .filter(\.isVisibleToCurrentUser)

        return DailyChallengeSnapshot(
            currentUserID: currentUserID,
            coupleDayID: rows.first?.coupleDayID,
            questions: questions,
            refreshedAt: refreshedAt
        )
    }
}
