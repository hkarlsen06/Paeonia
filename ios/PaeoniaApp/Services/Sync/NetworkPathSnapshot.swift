import Foundation
import Network

/// What the phone's network path looks like, reduced to what decides whether writes that
/// failed offline should go again.
nonisolated struct NetworkPathSnapshot: Equatable, Sendable {
    /// The path can carry traffic.
    var isOnline: Bool
    /// The interfaces, interface types and gateways the path uses. Joining a network
    /// changes it even when `isOnline` stays true.
    var route: [String]

    /// Whether the phone may reach the server now after it could not. An always-on VPN can
    /// keep its tunnel interface up in airplane mode, so the path may stay online the whole
    /// time and only its route changes when Wi-Fi comes back.
    /// Any online path that differs from the one before counts. The first reading only
    /// describes the network the app started on, and the run at launch covers it.
    func mayHaveReconnected(since previous: NetworkPathSnapshot?) -> Bool {
        guard isOnline, let previous else {
            return false
        }
        return self != previous
    }
}

nonisolated extension NetworkPathSnapshot {
    init(_ path: NWPath) {
        let usedTypes: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .loopback, .other]
        isOnline = path.status == .satisfied
        route = path.availableInterfaces.map { "\($0.name):\($0.type)" }
            + usedTypes.filter(path.usesInterfaceType).map { "uses:\($0)" }
            + path.gateways.map { "gateway:\($0)" }
    }

    /// Every change to the phone's network path, starting with the current one.
    static func updates() -> AsyncStream<NetworkPathSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                for await path in NWPathMonitor() {
                    continuation.yield(NetworkPathSnapshot(path))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
