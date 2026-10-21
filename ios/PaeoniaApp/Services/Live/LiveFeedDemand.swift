import Foundation

/// What the phone needs live data for right now. Screens publish the topics they
/// show, and the `LiveSyncCoordinator` starts and stops the feeds that serve
/// them. It exists so a view never reaches into the coordinator.
///
/// Two kinds of demand:
/// - Held: a source (the visible tab, the games the partner plays) holds a set of
///   topics until it publishes another set. A feed runs while any source wants it.
/// - Touched: a moment (the app came to the front, a game push arrived) starts
///   the feeds of a topic for the coordinator's linger time, then lets them go.
@MainActor
final class LiveFeedDemand {
    static let shared = LiveFeedDemand()

    /// Who holds topics. A source replaces its own topics and leaves the others alone.
    nonisolated enum Source: Hashable {
        case visibleTab
        case partnerGames
    }

    nonisolated enum Event: Sendable {
        /// Every held topic. The sequence orders events that reach the
        /// coordinator out of order, and the highest one wins.
        case held(Set<LiveFeedTopic>, sequence: Int)
        case touched(Set<LiveFeedTopic>)
    }

    private var topicsBySource: [Source: Set<LiveFeedTopic>] = [:]
    private var sequence = 0
    private var sink: (@Sendable (Event) async -> Void)?

    /// Sends events to `sink` from now on, starting with the topics held so far.
    /// A later call replaces the sink.
    func attach(_ sink: @escaping @Sendable (Event) async -> Void) {
        self.sink = sink
        sendHeld()
    }

    /// Replaces what `source` holds.
    func hold(_ topics: Set<LiveFeedTopic>, for source: Source) {
        guard (topicsBySource[source] ?? []) != topics else {
            return
        }
        topicsBySource[source] = topics
        sendHeld()
    }

    /// Asks for the feeds of `topics` to run for a short while.
    func touch(_ topics: Set<LiveFeedTopic>) {
        send(.touched(topics))
    }

    private func sendHeld() {
        sequence += 1
        send(.held(topicsBySource.values.reduce(into: []) { $0.formUnion($1) }, sequence: sequence))
    }

    private func send(_ event: Event) {
        guard let sink else {
            return
        }
        Task { await sink(event) }
    }
}
