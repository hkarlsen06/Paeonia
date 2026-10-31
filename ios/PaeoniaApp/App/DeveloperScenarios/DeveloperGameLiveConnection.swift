#if DEBUG
  import Foundation
  import PencilKit

  /// Rejoins the simulated room and answers presence and canvas requests.
  final class DeveloperGameLiveConnection: WidgetLiveConnection {
    var onStart: ((WidgetLiveConnection) -> Void)?
    var partnerRole: WidgetLivePresence.Role?
    var partnerCanvas: PKDrawing?

    override func start() { onStart?(self) }

    override func send(_ message: WidgetLiveMessage) {
      guard message.type == .hello, let partnerRole else { return }
      if message.needsCanvas == true {
        guard let partnerCanvas else { return }
        onMessage?(WidgetLiveMessage(
          type: .ops,
          side: Double(GameCanvas.canonicalSide),
          upserts: partnerCanvas.dataRepresentation().base64EncodedString(),
          snapshot: true
        ))
      }
      onMessage?(WidgetLiveMessage(type: .hello, from: "partner", role: partnerRole.rawValue))
    }
  }
#endif
