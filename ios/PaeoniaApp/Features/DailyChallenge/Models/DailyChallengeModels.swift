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

    /// The backend rejects answer text longer than this, counted in code points after
    /// trimming (`submit_daily_answer` / `update_daily_answer_text`). A rejected
    /// queued answer would retry forever, so the composer stops it before sending.
    static let maxTextLength = 2_000

    /// The length the backend measures: code points of the trimmed text.
    static func measuredLength(of text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
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
/// and media ids together in a single payload — so this carries any combination
/// (e.g. a photo *and* a caption), and the service maps whatever is present.
nonisolated struct DailyAnswerPayload: Equatable, Sendable {
    var text: String?
    var partnerChoiceUserID: UUID?
    var mediaAssetIDs: [UUID]

    init(text: String? = nil, partnerChoiceUserID: UUID? = nil, mediaAssetIDs: [UUID] = []) {
        self.text = text
        self.partnerChoiceUserID = partnerChoiceUserID
        self.mediaAssetIDs = mediaAssetIDs
    }

    var isEmpty: Bool {
        (text?.isEmpty ?? true) && partnerChoiceUserID == nil && mediaAssetIDs.isEmpty
    }
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

    /// The pickable person for a chosen user id, so a revealed partner-choice answer
    /// can show the same avatar used while answering. Nil when identity isn't known.
    func option(for userID: UUID) -> Option? {
        partnerChoiceOptions?.first { $0.id == userID }
    }

    /// The partner's name for an answer header or a revealed pick — their nickname, or
    /// a neutral "Partner" fallback when it isn't known yet.
    var partnerName: String {
        partnerDisplayName ?? String(localized: .dailyChallengeChoicePartnerFallback)
    }
}

nonisolated enum DailyQuestionInstanceStatus: Equatable, Hashable, Sendable {
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

nonisolated struct DailyQuestionAnswerSummary: Equatable, Hashable, Sendable {
    let id: UUID
    let answeredAt: Date
}

nonisolated struct DailyQuestionAnswerDetail: Equatable, Hashable, Sendable {
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

    /// A partner-choice answer carrying only the pick — no caption, no media — so the
    /// only thing it renders is the chosen person. Used to decide when two identical
    /// picks can collapse into one shared answer.
    var isPurePartnerChoice: Bool {
        selectedUserID != nil && (textBody?.isEmpty ?? true) && mediaAssetIDs.isEmpty
    }
}

nonisolated enum DailyQuestionOrigin: Equatable, Hashable, Sendable {
    case own
    case partner
}

nonisolated struct DailyChallengeQuestion: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let coupleDayID: UUID
    let coupleID: UUID
    let localDate: String
    /// The couple-local date this question effectively belongs to — the day of its most
    /// recent answer. Matches `localDate` for live/today questions; in history it can be
    /// a later day when an exchange was finished after midnight. The history overview
    /// groups on this so a late-night exchange shows under the day it was completed.
    let effectiveLocalDate: String
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
    var ownAnswer: DailyQuestionAnswerSummary?
    let partnerAnswer: DailyQuestionAnswerSummary?
    let canViewPartnerAnswer: Bool
    var ownAnswerDetail: DailyQuestionAnswerDetail?
    let partnerAnswerDetail: DailyQuestionAnswerDetail?
    let origin: DailyQuestionOrigin
    /// Whether this row belongs to the active day returned by the backend. Carried
    /// unresolved exchanges from older days stay visible in the Questions tab, but
    /// they must not affect today's Home card or own-question progress.
    let isCurrentDay: Bool
    /// When the user first saw the partner's answer, on any of their devices.
    var partnerAnswerSeenAt: Date?
    /// When the partner first saw the user's answer.
    var ownAnswerSeenByPartnerAt: Date?
    /// How many earlier days the user answered this question, in this couple.
    var earlierRoundCount = 0
    /// The couple-local date (`yyyy-MM-dd`) of the user's latest earlier answer to it.
    var latestEarlierRoundLocalDate: String?
    /// Some day of this question has answers from both partners, so its chat can start.
    var hasSharedRound = false

    /// The single person both partners picked when a partner-choice exchange has the
    /// *same* viewable pick on both sides and nothing else to show. When set, the two
    /// otherwise-identical answer rows collapse into one shared answer headed by both
    /// names. Nil unless both answers are pure same-person picks and the partner's is
    /// viewable, so any caption, media, or differing pick keeps the rows separate.
    var sharedPartnerChoiceUserID: UUID? {
        guard
            let own = ownAnswerDetail,
            let partner = partnerAnswerDetail,
            partner.canViewAnswer,
            let chosen = own.selectedUserID,
            chosen == partner.selectedUserID,
            own.isPurePartnerChoice,
            partner.isPurePartnerChoice
        else { return nil }
        return chosen
    }

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

    /// Questions that let the user answer with text *and* a photo or partner-choice in
    /// one go (both composers shown together, each optional) rather than picking a
    /// single kind. The combo must be exactly text + photo or text + partner-choice;
    /// voice and any other shape keep the single-kind picker. The backend already
    /// stores text alongside media/choice on one answer.
    var combinedSecondaryKind: DailyChallengeAnswerKind? {
        let kinds = Set(composableAnswerKinds)
        guard kinds.contains(.text) else { return nil }
        let others = kinds.subtracting([.text])
        guard others == [.photo] || others == [.partnerChoice] else { return nil }
        return others.first
    }

    var usesCombinedCompose: Bool {
        combinedSecondaryKind != nil
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
            status != .shuffled,
            // Combined answers can hold media, which can't be edited, so the whole
            // answer is locked once sent (same rule as any media answer).
            !usesCombinedCompose
        else { return nil }

        if supportsTextAnswer { return .text }
        if supportsPartnerChoiceAnswer { return .partnerChoice }
        return nil
    }

    /// Whether the user may still change their own answer (text or partner-choice).
    var canEditOwnAnswer: Bool {
        editableAnswerKind != nil
    }

    /// A partner's question the user can still answer — a "to-do" that should surface
    /// above already-handled cards in the Questions tab so it's never buried under the
    /// recency timeline.
    var isAwaitingCurrentUserAnswer: Bool {
        origin == .partner && isAvailableToAnswer
    }

    /// The most recent answer time on this question — the later of the user's and the
    /// partner's answer — falling back to the day's start when neither is set. The
    /// shared sort key for the read overviews (the Questions tab's single list and the
    /// history's within-day order), so both read most-recent-first the same way.
    var latestAnswerDate: Date {
        [ownAnswer?.answeredAt, partnerAnswer?.answeredAt]
            .compactMap { $0 }
            .max() ?? startsAt
    }

    /// The user can read the partner's answer but hasn't seen it yet, on any device
    /// (`partnerAnswerSeenAt`) or on this phone (`seen`, which counts before the server
    /// hears about it). Opening the question's page or the answer flow's reveal marks
    /// it seen.
    func hasNewPartnerAnswer(seen: Set<UUID>) -> Bool {
        hasRevealedPartnerAnswer && partnerAnswerSeenAt == nil && !seen.contains(id)
    }
}
