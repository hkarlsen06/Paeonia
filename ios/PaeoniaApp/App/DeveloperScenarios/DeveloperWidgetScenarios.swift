#if DEBUG
  import Foundation
  import SwiftUI

  @MainActor
  struct DeveloperWidgetScenarioView: View {
    let scenario: DeveloperScenario
    @State private var historyEditing = MediaAlternativeEditingService(
      pending: InMemoryPendingSyncOperationRepository(),
      cache: MediaAlternativeCacheUpdater(chat: InMemoryThreadChatCache(),
                                          stories: DeveloperAvatarStoriesCache(StoriesSnapshot()),
                                          daily: DeveloperLocalFlowSnapshotCache())
    )

    private var historyContext: ThreadChatContext {
      var context = ThreadChatContext(coupleID: DeveloperScenarioFixture.coupleID)
      context.participants.currentUserID = DeveloperScenarioFixture.currentUserID
      context.operationProvider = DeveloperScenarioOperationProvider()
      return context
    }

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
        .environment(\.threadChatContext, historyContext)
        .environment(\.mediaAlternativeEditingService, historyEditing)
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

    func getOrCreateCanvas() throws -> WidgetCanvasReference {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
      coupleID _: UUID, canvasID _: UUID, revisionID _: UUID,
      operation _: WidgetCanvasClientOperation
    ) throws -> MediaUploadReservation {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(reservation _: MediaUploadReservation, data _: Data) throws -> String {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func finalizeDrawingUpload(
      _: WidgetDrawingFinalizeInput, operation _: WidgetCanvasClientOperation
    ) throws -> FinalizedMediaUploadResponse {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
      _: WidgetDrawingRevisionSubmission, operation _: WidgetCanvasClientOperation
    ) throws -> WidgetDrawingRevisionResult {
      throw WidgetCanvasGatewayError.emptyResponse
    }
    func getCanvasState() throws -> WidgetCanvasState? {
      WidgetCanvasState(
        canvasID: canvasID,
        activeRevisionID: UUID(),
        activeRevisionAuthorUserID: DeveloperScenarioFixture.currentUserID,
        payloadMediaAssetID: UUID(),
        bounds: WidgetDrawingBounds(x: 0, y: 0, width: 260, height: 240, canvasSide: 320),
        revisionCreatedAt: DeveloperScenarioFixture.now, coupleID: DeveloperScenarioFixture.coupleID
      )
    }
    func signedPayloadURL(mediaAssetID _: UUID) throws -> URL? { nil }
    func listRevisions(
      canvasID _: UUID, limit _: Int, createdBefore: Date?, createdBeforeRevisionID _: UUID?
    ) throws -> [WidgetDrawingRevisionSummary] {
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

  actor DeveloperWidgetCanvasService: WidgetCanvasManaging {
    func capturePublicationTicket(for payload: WidgetDrawingUploadPayload) -> WidgetCanvasPublicationTicket {
      WidgetCanvasPublicationTicket(
        publicationID: payload.publicationID,
        generations: WidgetCanvasGenerations(privacy: 0, publication: 0), privacyEpoch: 0
      )
    }
    func acceptPublication(_: WidgetCanvasPublicationTicket, revisionID _: UUID) {}

    private var snapshot: WidgetCanvasSnapshot?

    init(snapshot: WidgetCanvasSnapshot? = nil) {
      self.snapshot = snapshot
    }

    func loadSavedDrawing() -> Data? { snapshot?.drawingData }
    func loadSavedSnapshot() -> WidgetCanvasSnapshot? { snapshot }
    func saveDrawing(
      _ drawingData: Data, canvasSize _: CGSize, authorName: String?, createdAt: Date
    ) throws {
      snapshot = WidgetCanvasSnapshot(
        drawingData: drawingData,
        authorName: authorName,
        createdAt: createdAt
      )
    }
    func clearForPrivacy() { snapshot = nil }
    func saveDescribedDrawing(
      _ data: Data, canvasSize: CGSize, authorName: String?, createdAt: Date,
      revisionID _: UUID?, accessibilityText: String?
    ) {
      snapshot = WidgetCanvasSnapshot(
        drawingData: data, authorName: authorName, createdAt: createdAt,
        canvasSide: canvasSize.width, accessibilityText: accessibilityText
      )
    }
    func hideForPrivacy() { snapshot = nil }
  }

  actor DeveloperWidgetCanvasUploader: WidgetCanvasUploading {
    func send(_: WidgetDrawingUploadPayload) -> WidgetDrawingDelivery { .delivered }
    func uploadPending(_: WidgetDrawingUploadPayload) throws {}
  }
#endif
