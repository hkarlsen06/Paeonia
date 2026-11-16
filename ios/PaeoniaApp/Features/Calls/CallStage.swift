import SwiftUI

/// The videos on the full call screen: the one that fills it, and the small previews in a corner.
nonisolated struct CallStage: Equatable {
    /// The video that fills the screen. Nil while the partner has no video, when their face and name
    /// show instead.
    let main: CallVideoSource?
    /// The other videos, in the order they stack from the corner.
    let previews: [CallVideoSource]

    /// Every video on screen, the one that fills it first.
    var sources: [CallVideoSource] {
        (main.map { [$0] } ?? []) + previews
    }
}

/// The order the person left the three videos in. The first one that is on fills the screen, and
/// the rest stack as previews. A tap on a preview swaps it with the big one, so the two trade places.
nonisolated struct CallStageOrder: Equatable {
    private(set) var order: [CallVideoSource] = [.partnerScreen, .partner, .local]

    /// Your own camera fills the screen only while there is another video to swap back to.
    func stage(for session: CallSession) -> CallStage {
        let shown = order.filter { Self.isShown($0, in: session) }
        guard let first = shown.first, first != .local || shown.count > 1 else {
            return CallStage(main: nil, previews: shown)
        }
        return CallStage(main: first, previews: Array(shown.dropFirst()))
    }

    /// Swaps `source` with the video that fills the screen now.
    mutating func bringForward(_ source: CallVideoSource, in session: CallSession) {
        guard let main = stage(for: session).main, main != source,
              let from = order.firstIndex(of: source), let to = order.firstIndex(of: main)
        else { return }
        order.swapAt(from, to)
    }

    /// The partner shared their screen to show it, so it fills the screen.
    mutating func showPartnerScreen() {
        order.removeAll { $0 == .partnerScreen }
        order.insert(.partnerScreen, at: 0)
    }

    static func isShown(_ source: CallVideoSource, in session: CallSession) -> Bool {
        if case .ended = session.phase { return false }
        return switch source {
        case .partner: session.isPartnerCameraOn
        case .partnerScreen: session.isPartnerSharingScreen
        case .local: session.isCameraOn
        }
    }
}

nonisolated extension CallVideoSource {
    /// A preview covers the same area as a 104 by 152 point tile, in the shape of its picture.
    static let previewArea: CGFloat = 104 * 152

    /// The preview's size, upright as the person holds the phone. Your own camera is wide while the
    /// phone is on its side, because the camera then sends wide pictures.
    func previewSize(in session: CallSession, sideways: Bool) -> CGSize {
        let ratio: CGFloat = switch self {
        case .local: sideways ? 152 / 104 : 104 / 152
        case .partner: session.partnerVideoAspectRatio ?? 104 / 152
        case .partnerScreen: session.partnerScreenAspectRatio ?? 9 / 19.5
        }
        return CGSize(width: (Self.previewArea * ratio).squareRoot(), height: (Self.previewArea / ratio).squareRoot())
    }
}

extension CallVideoSource {
    func accessibilityLabel(partnerName: String) -> Text {
        switch self {
        case .local: Text(.callsYourCamera)
        case .partner: Text(.callsPartnerCamera(partnerName))
        case .partnerScreen: Text(.callsPartnerScreen(partnerName))
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .local: "calls.video.local"
        case .partner: "calls.video.partner"
        case .partnerScreen: "calls.video.partnerScreen"
        }
    }
}
