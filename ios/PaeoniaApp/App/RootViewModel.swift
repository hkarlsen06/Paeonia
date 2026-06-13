import Observation

@MainActor
@Observable
final class RootViewModel {

    private let syncCoordinator: any SyncCoordinating

    private(set) var state: AppState = .launching

    init(syncCoordinator: (any SyncCoordinating)? = nil) {
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator()
    }

    func start() async {
        await syncCoordinator.start()
        state = .unauthenticated
    }
}
