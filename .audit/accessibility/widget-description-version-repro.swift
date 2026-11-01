import Foundation

nonisolated func writeLine(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

@main
struct DeferredDescriptionRepro {
    static func main() {
        var payload = WidgetSharePayload(
            revisionID: UUID().uuidString, authorName: "Alex", createdAt: Date(), renderedAt: Date(),
            privacyMode: .normal, isRedacted: false, contentHash: "same drawing", previews: [:], canvasSide: 320,
            accessibilityText: "Original", descriptionVersion: 1000
        )
        let operation = UUID()
        payload.applyDescription(.queued(text: "Correction A", operationID: operation))
        payload.applyDescription(.remote(text: "Newer correction B", version: 1002))
        payload.applyDescription(.accepted(text: "Correction A", version: 1001, operationID: operation))
        writeLine("Final visible description: \(payload.accessibilityText ?? "nil")")
        writeLine("Final server version: \(payload.descriptionVersion ?? -1)")
        writeLine("Expected newer correction B, version 1002")
    }
}
