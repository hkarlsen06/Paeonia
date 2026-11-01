import Foundation

nonisolated protocol WidgetDrawingDescriptionCaching: Sendable {
    func updateDescription(_ update: WidgetDrawingDescriptionUpdate, revisionID: UUID,
                           privacyToken: LocalPrivacyWriteGuard.Token) async throws
}

extension WidgetCanvasService: WidgetDrawingDescriptionCaching {}
