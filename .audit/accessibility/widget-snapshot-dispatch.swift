import Foundation

nonisolated func writeLine(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

nonisolated protocol SnapshotSource: Sendable {
    func snapshot() async -> String
}
extension SnapshotSource {
    func snapshot() async -> String { "protocol fallback" }
}
actor StoredSnapshot: SnapshotSource {
    func snapshot() -> String { "stored metadata" }
}
actor ExplicitStoredSnapshot: SnapshotSource {
    func snapshot() async -> String { "stored metadata" }
}
@main struct Probe {
    static func main() async {
        let concrete = StoredSnapshot()
        let erased: any SnapshotSource = concrete
        writeLine("Synchronous actor, concrete: \(await concrete.snapshot())")
        writeLine("Synchronous actor, protocol: \(await erased.snapshot())")
        let explicit = ExplicitStoredSnapshot()
        let explicitErased: any SnapshotSource = explicit
        writeLine("Async actor, concrete: \(await explicit.snapshot())")
        writeLine("Async actor, protocol: \(await explicitErased.snapshot())")
    }
}
