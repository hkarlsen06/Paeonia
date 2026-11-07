import Foundation
import Observation

@Observable
final class GameLiveReactions {
    private(set) var flights: [GameLiveReactionFlight] = []
    @ObservationIgnored private var removalTask: Task<Void, Never>?

    func show(_ reaction: GameLiveReaction) {
        flights.removeAll { Date().timeIntervalSince($0.start) >= GameLiveReactionFlight.duration }
        flights.append(GameLiveReactionFlight(reaction: reaction))
        flights = Array(flights.suffix(20))
        removalTask?.cancel()
        removalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GameLiveReactionFlight.duration))
            guard !Task.isCancelled else { return }
            self?.flights.removeAll()
        }
    }

    func clear() {
        removalTask?.cancel()
        removalTask = nil
        flights.removeAll()
    }
}
