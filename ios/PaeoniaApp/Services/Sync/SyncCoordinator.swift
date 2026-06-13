protocol SyncCoordinating: Actor {
    func start()
}

actor SyncCoordinator: SyncCoordinating {
    private var hasStarted = false

    func start() {
        hasStarted = true
        // Real sync orchestration starts once local models and Supabase contracts exist.
    }
}
