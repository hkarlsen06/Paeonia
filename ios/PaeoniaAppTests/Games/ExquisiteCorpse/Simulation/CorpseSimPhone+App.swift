import Foundation
@testable import PaeoniaApp

// The app moves to the background and back, the screen opens and closes, the network comes and goes.
extension CorpseSimPhone {
    func openScreen() {
        guard isAlive, !isScreenOpen, let viewModel else { return }
        isScreenOpen = true
        log.add("\(name) open screen")
        startTask = Task { await viewModel.start() }
    }

    func closeScreen() {
        guard isAlive, isScreenOpen, let viewModel else { return }
        log.add("\(name) close screen")
        startTask?.cancel()
        startTask = nil
        viewModel.stop()
        isScreenOpen = false
    }

    func moveToBackground() {
        guard isAlive, isForeground else { return }
        log.add("\(name) background")
        isForeground = false
        if isScreenOpen {
            viewModel?.scenePhaseChanged(isActive: false)
        }
    }

    func moveToForeground() {
        guard isAlive, !isForeground else { return }
        log.add("\(name) foreground")
        isForeground = true
        if isScreenOpen {
            viewModel?.scenePhaseChanged(isActive: true)
        }
        Task { await self.sync() }
    }

    func setOnline(_ online: Bool) {
        guard network.isOnline != online else { return }
        network.isOnline = online
        log.add("\(name) \(online ? "online" : "offline")")
        if !online {
            socket?.dropSilently()
        } else if isAlive {
            Task { await self.sync() }
        }
    }

    /// The open screen's 30-second heartbeat, which the driver runs as it moves the clock.
    func heartbeat() {
        guard let viewModel = activeViewModel, let gateway else { return }
        Task { try? await gateway.setPresence(.exquisiteCorpse, isPresent: true) }
        viewModel.now = clock.now
        viewModel.recompute()
    }

    func tick() {
        guard isAlive, let viewModel else { return }
        viewModel.now = clock.now
        if isScreenOpen {
            viewModel.recompute()
        }
    }

    func reconnectRelay() {
        socket?.reconnectIfNeeded()
    }
}
