import Foundation

nonisolated func writeLine(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}
@main struct PendingDescriptionRepro {
    static func main() {
        var payload = WidgetSharePayload(
            revisionID: UUID().uuidString, authorName: "Alex", createdAt: Date(), renderedAt: Date(),
            privacyMode: .normal, isRedacted: false, contentHash: "same drawing", previews: [:], canvasSide: 320,
            accessibilityText: "Original", descriptionVersion: 1000
        )
        let first = UUID()
        let second = UUID()
        payload.applyDescription(.queued(text: "Correction A", operationID: first))
        // The outbox contains B, but its optimistic file write failed, so this payload still names A.
        payload.applyDescription(.accepted(text: "Correction B", version: 1002, operationID: second))
        writeLine("Old optimistic ID remains after latest durable correction B accepted: \(payload.pendingDescriptionOperationID == first)")
        writeLine("Visible description after acceptance: \(payload.accessibilityText ?? "nil")")
    }
}
