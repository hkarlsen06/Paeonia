#if DEBUG
  import Foundation
  import PencilKit

  /// The partner's drawing for every download: the fixture umbrella. A stalled
  /// download waits until the screen goes away.
  struct DeveloperGameDrawingTransfer: GameDrawingTransferring {
    var stallsDownloads = false

    func uploadDrawing(
      _: Data,
      parent _: GameUploadParent,
      coupleID _: UUID,
      reserveOperation _: SyncClientOperation,
      finalizeOperation _: SyncClientOperation
    ) throws -> UUID {
      DeveloperGamesFixture.assetID
    }

    func downloadDrawing(mediaAssetID _: UUID) async throws -> Data {
      if stallsDownloads {
        try await Task.sleep(for: .seconds(86_400))
      }
      return await MainActor.run { DeveloperGamesFixture.umbrella().dataRepresentation() }
    }
  }
#endif
