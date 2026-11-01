import Foundation

nonisolated protocol WidgetDrawingDescriptionCaching: Sendable {
    func updateDescription(_ update: WidgetDrawingDescriptionUpdate, revisionID: UUID,
                           privacyToken: LocalPrivacyWriteGuard.Token) async
}

extension WidgetCanvasService: WidgetDrawingDescriptionCaching {}
