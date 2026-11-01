import Foundation

actor WidgetDescriptionIsolationProbe {
    func merge(in root: URL, update: WidgetDrawingDescriptionUpdate) throws {
        _ = try WidgetSharePayload.updateFile(in: root) { payload in
            payload.applyDescription(update)
        }
    }
}
