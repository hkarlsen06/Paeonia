import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// Presentation state for the Questions history flow. Reads the couple's full
/// answered-question history once, groups it into day sections, and keeps the last
/// good content visible across a failed refresh so a transient blip never blanks the
/// screen.
@MainActor
@Observable
final class DailyChallengeHistoryViewModel: Identifiable, PresentationReadinessProviding {
    /// Stable identity so the screen can present it with `.fullScreenCover(item:)`.
    nonisolated let id = UUID()

    enum ViewState: Equatable {
        case loading
        case content(Content)
        case empty
        case failed
    }

    /// What the loaded history shows: the partner's questions still waiting for the
    /// user's answer (actionable, shown at the top with a CTA) and the completed
    /// exchanges grouped into days below. Either can be empty as long as the other
    /// isn't — when both are empty the state is `.empty` instead.
    struct Content: Equatable {
        var pendingPartnerQuestions: [DailyChallengeQuestion]
        var days: [DailyChallengeHistoryDay]
    }

    enum Notice: Equatable {
        case loadFailed
    }

    private let service: any DailyChallengeServicing
    private let chatService: any DailyQuestionChatServicing
    /// The partner's questions the user can still answer, read live from the daily
    /// challenge so the history shows the same actionable cards the Questions tab does.
    /// These are carried-forward exchanges (partner answered, the user hasn't), not part
    /// of the answered-history read model, so they come from here rather than the RPC.
    private let pendingPartnerQuestionsProvider: () -> [DailyChallengeQuestion]
    let currentUserID: UUID?
    private(set) var participants: DailyChallengeParticipants
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "DailyChallengeHistory"
    )
    #endif

    private(set) var state: ViewState = .loading
    private(set) var notice: Notice?
    private(set) var threadSummariesByInstanceID: [UUID: DailyQuestionThreadSummary] = [:]
    /// Numbers each `load()` call in the order it started.
    private var loadSequence = 0
    /// The number of the newest load that has written a result. A load that started
    /// earlier never writes after it, so a slow older read can't overwrite a newer one.
    private var lastAppliedLoad = 0

    init(
        service: any DailyChallengeServicing,
        chatService: (any DailyQuestionChatServicing)? = nil,
        currentUserID: UUID?,
        participants: DailyChallengeParticipants = DailyChallengeParticipants(),
        pendingPartnerQuestions: @escaping () -> [DailyChallengeQuestion] = { [] }
    ) {
        self.service = service
        self.chatService = chatService ?? EmptyDailyQuestionChatService()
        self.currentUserID = currentUserID
        self.participants = participants
        self.pendingPartnerQuestionsProvider = pendingPartnerQuestions
    }

    /// Ready once the first load has settled — to content, empty, or a final error —
    /// so the cover holds its calm loading surface until there is something stable to
    /// show, never a flash of the empty state before content arrives.
    var isPresentationReady: Bool {
        state != .loading
    }

    /// Loads (or reloads) the history. The first load drives the loading → content /
    /// empty / failed state. A reload that fails while content is already on screen
    /// keeps that content and surfaces a recoverable banner instead of a full-screen
    /// error.
    ///
    /// Loads can overlap (first load, pull to refresh, retry, reload after answering),
    /// so each one takes a number when it starts and only writes if no newer load has
    /// written already. A cancelled load writes nothing and leaves the state alone; the
    /// next load settles it.
    func load() async {
        guard let currentUserID else {
            state = .empty
            return
        }

        loadSequence += 1
        let loadNumber = loadSequence

        if !hasContent { state = .loading }

        applyThreadSummaries(await chatService.cachedThreadSummaries(ownerUserID: currentUserID))
        let threadSummariesTask = Task { [chatService] in
            try? await chatService.refreshThreadSummaries(ownerUserID: currentUserID)
        }

        do {
            let questions = try await service.loadHistory(currentUserID: currentUserID)
            let summaries = await threadSummariesTask.value
            guard loadNumber > lastAppliedLoad else { return }
            lastAppliedLoad = loadNumber
            if let summaries {
                applyThreadSummaries(summaries)
            }
            settle(days: DailyChallengeHistory.grouped(questions))
        } catch {
            guard !isCancellation(error) else {
                threadSummariesTask.cancel()
                return
            }
            guard loadNumber > lastAppliedLoad else { return }
            showLoadFailure(error)
        }
    }

    private var hasContent: Bool {
        if case .content = state { return true }
        return false
    }

    private func showLoadFailure(_ error: Error) {
        logFailure("Loading the question history failed", error)
        if hasContent {
            // Keep what's on screen; nudge the user with a recoverable banner.
            notice = .loadFailed
        } else {
            state = .failed
        }
    }

    /// Re-reads only the "waiting for you" section from the daily challenge, without
    /// fetching the history again. The daily challenge changes while the history is
    /// open (the partner answers another question), and the completed days don't.
    /// Does nothing until a load has settled to content or empty; a load reads the
    /// section itself.
    func refreshPendingPartnerQuestions() {
        guard currentUserID != nil else { return }
        switch state {
        case let .content(content):
            settle(days: content.days)
        case .empty:
            settle(days: [])
        case .loading, .failed:
            return
        }
    }

    func threadPreview(for instanceID: UUID) -> String? {
        threadSummariesByInstanceID[instanceID]?.lastMessageBody
    }

    func refreshThreadSummaries() async {
        guard let currentUserID else { return }
        let cached = await chatService.cachedThreadSummaries(ownerUserID: currentUserID)
        applyThreadSummaries(cached)
        if let remote = try? await chatService.refreshThreadSummaries(ownerUserID: currentUserID) {
            applyThreadSummaries(remote)
        }
    }

    /// Keeps the message previews current while the screen is open, until the calling
    /// task is cancelled. A reply from the partner shows up without a pull to refresh.
    func observeThreadSummaries() async {
        guard let currentUserID else { return }
        for await change in LocalStoreChanges.changes(in: .dailyChat) where change.ownerUserID == currentUserID {
            applyThreadSummaries(await chatService.cachedThreadSummaries(ownerUserID: currentUserID))
        }
    }

    /// Updates the partners' display names and photos without reloading — cosmetic
    /// identity that may arrive after the cover opens. Mirrors the daily challenge's
    /// separation of reloading identity from rendering identity.
    func refreshParticipants(_ participants: DailyChallengeParticipants) {
        self.participants = participants
    }

    func dismissNotice() {
        notice = nil
    }

    private func applyThreadSummaries(_ summaries: [DailyQuestionThreadSummary]) {
        threadSummariesByInstanceID = Dictionary(
            summaries.map { ($0.instanceID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Builds the loaded state from the completed days plus the partner's waiting
    /// questions. The waiting section is read from the daily challenge on every call, so
    /// it is current whether the days were just loaded or only the section is refreshed.
    private func settle(days: [DailyChallengeHistoryDay]) {
        let answeredInstanceIDs = Set(days.flatMap { $0.questions.map(\.id) })
        let pending = pendingPartnerQuestions(excluding: answeredInstanceIDs)
        let newState: ViewState = days.isEmpty && pending.isEmpty
            ? .empty
            : .content(Content(pendingPartnerQuestions: pending, days: days))
        if newState != state {
            state = newState
        }
    }

    /// The partner's still-unanswered questions for the top of the history, most recent
    /// partner answer first. Any instance already present in the answered history is
    /// dropped, so a question can never show as both "waiting for you" and "completed"
    /// (e.g. mid-reload after you reply).
    private func pendingPartnerQuestions(
        excluding answeredInstanceIDs: Set<UUID>
    ) -> [DailyChallengeQuestion] {
        pendingPartnerQuestionsProvider()
            .filter { !answeredInstanceIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.partnerAnswer?.answeredAt ?? lhs.startsAt
                let rhsDate = rhs.partnerAnswer?.answeredAt ?? rhs.startsAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.slotNumber != rhs.slotNumber { return lhs.slotNumber < rhs.slotNumber }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func logFailure(_ context: String, _ error: Error) {
        #if DEBUG
        logger.error("\(context, privacy: .public): \(String(describing: error))")
        #endif
    }

    /// A cancelled load (a superseded reload or the screen going away) is not a real
    /// failure: Foundation reports it as `URLError.cancelled` rather than Swift's
    /// `CancellationError`, so both are swallowed. See the `.task(id:)` note in
    /// AGENTS.md.
    private nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

extension DailyChallengeHistoryViewModel.Notice {
    var title: LocalizedStringResource {
        switch self {
        case .loadFailed:
            .dailyChallengeHistoryLoadFailedTitle
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .loadFailed:
            .dailyChallengeHistoryLoadFailedMessage
        }
    }
}
