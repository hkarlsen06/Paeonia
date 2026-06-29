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
        case content([DailyChallengeHistoryDay])
        case empty
        case failed
    }

    enum Notice: Equatable {
        case loadFailed
    }

    private let service: any DailyChallengeServicing
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

    init(
        service: any DailyChallengeServicing,
        currentUserID: UUID?,
        participants: DailyChallengeParticipants = DailyChallengeParticipants()
    ) {
        self.service = service
        self.currentUserID = currentUserID
        self.participants = participants
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
    func load() async {
        guard let currentUserID else {
            state = .empty
            return
        }

        let hasContent: Bool
        if case .content = state { hasContent = true } else { hasContent = false }
        if !hasContent { state = .loading }

        do {
            let questions = try await service.loadHistory(currentUserID: currentUserID)
            let days = DailyChallengeHistory.grouped(questions)
            state = days.isEmpty ? .empty : .content(days)
        } catch {
            guard !isCancellation(error) else { return }
            logFailure("Loading the question history failed", error)
            if hasContent {
                // Keep what's on screen; nudge the user with a recoverable banner.
                notice = .loadFailed
            } else {
                state = .failed
            }
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
