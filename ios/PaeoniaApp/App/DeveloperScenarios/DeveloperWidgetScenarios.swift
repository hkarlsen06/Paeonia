#if DEBUG
  import Foundation
  import SwiftUI

  @MainActor
  struct DeveloperWidgetScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      switch scenario {
      case .widgetHistoryEmpty:
        WidgetDrawingHistoryView(
          viewModel: WidgetDrawingHistoryViewModel(
            gateway: NoOpWidgetCanvasGateway(),
            identity: WidgetSyncIdentity(
              currentUserID: DeveloperScenarioFixture.currentUserID,
              currentDisplayName: "Alex",
              partnerDisplayName: "Robin"
            )
          ),
          thumbnailLoader: NoOpWidgetRevisionThumbnailLoader()
        )
      case .widgetHistoryPopulated:
        WidgetDrawingHistoryView(
          viewModel: WidgetDrawingHistoryViewModel(
            gateway: DeveloperWidgetHistoryGateway(),
            identity: WidgetSyncIdentity(
              currentUserID: DeveloperScenarioFixture.currentUserID,
              currentDisplayName: "Alex",
              partnerDisplayName: "Robin"
            )
          ),
          thumbnailLoader: NoOpWidgetRevisionThumbnailLoader()
        )
      default:
        NavigationStack {
          WidgetDrawingView(
            viewModel: WidgetDrawingViewModel(
              authorName: "Alex",
              service: DeveloperWidgetCanvasService(),
              uploader: DeveloperWidgetCanvasUploader()
            ),
            historyViewModel: WidgetDrawingHistoryViewModel(
              gateway: NoOpWidgetCanvasGateway(),
              identity: WidgetSyncIdentity(
                currentUserID: DeveloperScenarioFixture.currentUserID,
                currentDisplayName: "Alex",
                partnerDisplayName: "Robin"
              )
            ),
            historyThumbnailLoader: NoOpWidgetRevisionThumbnailLoader()
          )
        }
      }
    }
  }

  private struct DeveloperWidgetHistoryGateway: WidgetCanvasGateway {
    private let canvasID = UUID(uuidString: "99999999-9999-9999-9999-999999999999") ?? UUID()

    func getOrCreateCanvas() async throws -> WidgetCanvasReference {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
      coupleID _: UUID, canvasID _: UUID, revisionID _: UUID,
      operation _: WidgetCanvasClientOperation
    ) async throws -> PendingMediaUploadResponse {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(bucket _: String, storagePath _: String, data _: Data) async throws {}
    func finalizeDrawingUpload(
      _: WidgetDrawingFinalizeInput, operation _: WidgetCanvasClientOperation
    ) async throws -> FinalizedMediaUploadResponse {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
      _: WidgetDrawingRevisionSubmission, operation _: WidgetCanvasClientOperation
    ) async throws -> WidgetDrawingRevisionResult {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func getCanvasState() async throws -> WidgetCanvasState? {
      WidgetCanvasState(
        canvasID: canvasID,
        activeRevisionID: UUID(),
        activeRevisionAuthorUserID: DeveloperScenarioFixture.currentUserID,
        payloadMediaAssetID: UUID(),
        bounds: WidgetDrawingBounds(x: 0, y: 0, width: 260, height: 240, canvasSide: 320),
        revisionCreatedAt: DeveloperScenarioFixture.now
      )
    }
    func signedPayloadURL(mediaAssetID _: UUID) async throws -> URL? { nil }
    func listRevisions(
      canvasID _: UUID, limit _: Int, createdBefore: Date?, createdBeforeRevisionID _: UUID?
    ) async throws -> [WidgetDrawingRevisionSummary] {
      guard createdBefore == nil else { return [] }
      return [
        revision(author: DeveloperScenarioFixture.currentUserID, age: 3_600),
        revision(author: DeveloperScenarioFixture.partnerUserID, age: 86_400),
        revision(author: DeveloperScenarioFixture.currentUserID, age: 172_800),
      ]
    }

    private func revision(author: UUID, age: TimeInterval) -> WidgetDrawingRevisionSummary {
      WidgetDrawingRevisionSummary(
        revisionID: UUID(),
        authorUserID: author,
        payloadMediaAssetID: UUID(),
        bounds: WidgetDrawingBounds(x: 10, y: 12, width: 240, height: 220, canvasSide: 320),
        createdAt: DeveloperScenarioFixture.now.addingTimeInterval(-age)
      )
    }
  }

  private actor DeveloperWidgetCanvasService: WidgetCanvasManaging {
    private var snapshot: WidgetCanvasSnapshot?

    func loadSavedDrawing() async -> Data? { snapshot?.drawingData }
    func loadSavedSnapshot() async -> WidgetCanvasSnapshot? { snapshot }
    func saveDrawing(
      _ drawingData: Data, canvasSize _: CGSize, authorName: String?, createdAt: Date
    ) async throws {
      snapshot = WidgetCanvasSnapshot(
        drawingData: drawingData,
        authorName: authorName,
        createdAt: createdAt
      )
    }
    func clearForPrivacy() async { snapshot = nil }
    func hideForPrivacy() async { snapshot = nil }
  }

  private actor DeveloperWidgetCanvasUploader: WidgetCanvasUploading {
    func enqueueUpload(_: WidgetDrawingUploadPayload) async {}
    func uploadPending(_: WidgetDrawingUploadPayload) async throws {}
  }
#endif
