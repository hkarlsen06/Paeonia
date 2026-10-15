import Foundation
import Observation
#if DEBUG
import OSLog
#endif

/// Loads the couple's answered-question history for the earlier-days section of the
/// Questions tab. It groups the questions into days and keeps the last good content
/// visible across a failed refresh, so a blip never blanks the section. Chat previews
/// and unread marks come from `DailyChallengeViewModel`, which the rows read directly.
@MainActor
@Observable
final class DailyChallengeHistoryViewModel {
    enum ViewState: Equatable {
        case loading
        case content([DailyChallengeHistoryDay])
        case empty
        case failed(PaeoniaFailure)
    }

    enum Notice: Equatable {
        case loadFailed(PaeoniaFailure)
    }

    private let service: any DailyChallengeServicing
    let currentUserID: UUID?
    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "DailyChallengeHistory"
    )
    #endif

    private(set) var state: ViewState = .loading
    private(set) var notice: Notice?
    /// Numbers each `load()` call in the order it started.
    private var loadSequence = 0
    /// The number of the newest load that has written a result. A load that started
    /// earlier never writes after it, so a slow older read can't overwrite a newer one.
    private var lastAppliedLoad = 0

    init(service: any DailyChallengeServicing, currentUserID: UUID?) {
        self.service = service
        self.currentUserID = currentUserID
    }

    /// Whether a screen that appears should start a load: nothing has loaded yet, or the
    /// last first load failed. Content and an empty result stay as they are until a
    /// pull to refresh or a new day asks for a reload.
    var needsLoad: Bool {
        switch state {
        case .loading, .failed: true
        case .content, .empty: false
        }
    }

    /// The loaded days without the questions in `shownIDs`, newest day first. The
    /// Questions tab lists today's questions above, so a question that is there never
    /// shows again under an earlier day. A day left with no questions is dropped.
    func days(excluding shownIDs: Set<UUID>) -> [DailyChallengeHistoryDay] {
        guard case let .content(days) = state else { return [] }
        return DailyChallengeHistory.removing(shownIDs, from: days)
    }

    /// Loads (or reloads) the history. The first load drives the loading → content /
    /// empty / failed state. A reload that fails while content is already on screen
    /// keeps that content and surfaces a recoverable banner instead of an error state.
    ///
    /// Loads can overlap (first load, pull to refresh, retry, a new day), so each one
    /// takes a number when it starts and only writes if no newer load has written
    /// already. A cancelled load writes nothing and leaves the state alone; the next
    /// load settles it.
    func load() async {
        guard let currentUserID else {
            state = .empty
            return
        }

        loadSequence += 1
        let loadNumber = loadSequence

        if !hasContent { state = .loading }

        do {
            let questions = try await service.loadHistory(currentUserID: currentUserID)
            guard loadNumber > lastAppliedLoad else { return }
            lastAppliedLoad = loadNumber
            let days = DailyChallengeHistory.grouped(questions)
            state = days.isEmpty ? .empty : .content(days)
        } catch {
            guard !isCancellation(error) else { return }
            guard loadNumber > lastAppliedLoad else { return }
            showLoadFailure(error)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private var hasContent: Bool {
        if case .content = state { return true }
        return false
    }

    private func showLoadFailure(_ error: Error) {
        logFailure("Loading the question history failed", error)
        if hasContent {
            // Keep what's on screen; nudge the user with a recoverable banner.
            notice = .loadFailed(PaeoniaFailure(error))
        } else {
            state = .failed(PaeoniaFailure(error))
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
        case .loadFailed(let failure):
            failure.dailyHistoryMessage
        }
    }
}

extension PaeoniaFailure {
    /// Only a phone without a connection is told to check it.
    var dailyHistoryMessage: LocalizedStringResource {
        self == .offline ? .dailyChallengeHistoryLoadFailedMessage : .commonLoadFailedMessage
    }
}
