import Foundation
import PencilKit
import UIKit

/// The partner's widget drawing, ready to unwrap. The drawing is at the canonical
/// game canvas size, which is what the replay plays at.
nonisolated struct PostPairingGift: Sendable {
    let revisionID: UUID
    let drawing: PKDrawing
}

/// What came of loading the partner's drawing.
nonisolated enum PostPairingGiftLoad: Sendable {
    /// The widget has no drawing, or the drawing on it is this person's own.
    case none
    case ready(PostPairingGift)
    /// The partner made a drawing, but it did not download.
    case failed(PaeoniaFailure)
}

/// Reads what the first day steps are decided from. Each read settles on its own
/// and never throws, so one failure only skips its own step.
nonisolated protocol PostPairingDataLoading: Sendable {
    func partnerGift(partnerUserID: UUID) async -> PostPairingGiftLoad
    /// This person's own drawing when it is the one on the couple's widget, as the
    /// widget shows it. Nil otherwise, or when it did not load.
    func ownDrawingImage(currentUserID: UUID) async -> UIImage?
    /// Nil when the preferences could not load.
    func questionTimeIsOn() async -> Bool?
    /// The partner answered questions today that this person can answer too.
    func partnerAnswersWaiting(currentUserID: UUID) async -> Bool
}

nonisolated struct LivePostPairingDataLoader: PostPairingDataLoading {
    var gateway: any WidgetCanvasGateway = WidgetDrawingHistoryFactory.makeGateway()
    var downloader: any WidgetPayloadDownloading = URLSessionWidgetPayloadDownloader()
    var preferences: (any NotificationPreferencesProviding)? = NotificationPreferencesServiceFactory.makeDefault()
    var dailyChallenge: any DailyChallengeServicing = DailyChallengeServiceFactory.makeDefault()

    func partnerGift(partnerUserID: UUID) async -> PostPairingGiftLoad {
        // Without the canvas state there is no telling whether a gift exists, so
        // a failure here skips the step quietly.
        guard let state = try? await gateway.getCanvasState(),
              state.activeRevisionAuthorUserID == partnerUserID,
              let revisionID = state.activeRevisionID,
              let mediaAssetID = state.payloadMediaAssetID
        else {
            return .none
        }

        do {
            guard let url = try await gateway.signedPayloadURL(mediaAssetID: mediaAssetID) else {
                return .failed(.other)
            }
            let data = try await downloader.download(from: url)
            let drawing = try PKDrawing(data: data)
            // Widget drawings keep the size of the canvas they were drawn on.
            let side = state.bounds?.canvasSide ?? Double(WidgetDrawingViewModel.fallbackCanvasSide)
            return .ready(PostPairingGift(
                revisionID: revisionID,
                drawing: drawing.scaled(fromSide: CGFloat(side), toSide: GameCanvas.canonicalSide)
            ))
        } catch {
            return .failed(PaeoniaFailure(error))
        }
    }

    func ownDrawingImage(currentUserID: UUID) async -> UIImage? {
        guard let state = try? await gateway.getCanvasState(),
              state.activeRevisionAuthorUserID == currentUserID,
              let mediaAssetID = state.payloadMediaAssetID,
              let url = try? await gateway.signedPayloadURL(mediaAssetID: mediaAssetID),
              let data = try? await downloader.download(from: url),
              let drawing = try? PKDrawing(data: data)
        else {
            return nil
        }
        let side = state.bounds?.canvasSide ?? Double(WidgetDrawingViewModel.fallbackCanvasSide)
        return await MainActor.run {
            var image: UIImage?
            // Light, like the widget's own previews, so the ink colors match.
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 2)
            }
            return image
        }
    }

    func questionTimeIsOn() async -> Bool? {
        try? await preferences?.loadNotificationPreferences().questionTime.isEnabled
    }

    func partnerAnswersWaiting(currentUserID: UUID) async -> Bool {
        let today = try? await dailyChallenge.loadToday(currentUserID: currentUserID)
        return today?.snapshot.hasQuestionsAwaitingAnswer ?? false
    }
}
