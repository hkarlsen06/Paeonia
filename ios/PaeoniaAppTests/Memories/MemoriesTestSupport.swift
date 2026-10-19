import Foundation
import UIKit
@testable import PaeoniaApp

struct MemoriesTestEnvironment {
    let viewModel: MemoriesViewModel
    let pendingStore: InMemoryPendingSyncOperationRepository
    let memoryStore: InMemoryMemoryRecordRepository
    let imageCache: MemoryTestImageCache
    let userID: UUID
    let coupleID: UUID
}

@MainActor
func makeMemoriesTestEnvironment(
    uploader: (any MemoryMediaUploading)?,
    imageProvider: (any MemoryMediaImageProviding)?,
    photoSaver: any PhotoLibrarySaving,
    draftStore: (any MemoryDraftStoring)?
) -> MemoriesTestEnvironment {
    let memoryStore = InMemoryMemoryRecordRepository()
    let pendingStore = InMemoryPendingSyncOperationRepository()
    let service = MemoryDataService(memoryStore: memoryStore, pendingOperationStore: pendingStore)
    let imageCache = MemoryTestImageCache()
    let viewModel = MemoriesViewModel(
        memoryService: service,
        operationProvider: MemoryTestOperationProvider(),
        mediaUploader: uploader,
        mediaImageCache: imageCache,
        imageProvider: imageProvider,
        photoSaver: photoSaver,
        draftStore: draftStore ?? makeIsolatedMemoryDraftStore()
    )
    return MemoriesTestEnvironment(
        viewModel: viewModel,
        pendingStore: pendingStore,
        memoryStore: memoryStore,
        imageCache: imageCache,
        userID: UUID(),
        coupleID: UUID()
    )
}

func makeMemoryTestImageData(color: UIColor) -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
    let image = renderer.image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    return image.jpegData(compressionQuality: 0.9) ?? Data()
}

@MainActor
func waitForMemoryTestCondition(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
final class MemoryTestOperationProvider: SyncClientOperationProviding {
    private var sequence: Int64 = 0
    private let clientID = UUID()

    func makeOperation() -> SyncClientOperation {
        sequence += 1
        return SyncClientOperation(clientID: clientID, clientSequence: sequence)
    }
}

actor MemoryTestImageCache {
    private(set) var cachedMediaAssetIDs: [UUID] = []

    func cacheImageData(_ data: Data, for mediaAssetID: UUID) {
        guard !data.isEmpty else { return }
        cachedMediaAssetIDs.append(mediaAssetID)
    }
}

extension MemoryTestImageCache: MemoryMediaImageCacheWriting {}

actor MemoryTestMediaUploader {
    private let shouldFail: Bool
    /// 1-based upload calls that fail.
    private let failingCalls: Set<Int>
    private let delay: Duration?
    private(set) var uploadCount = 0

    init(shouldFail: Bool = false, failingCalls: Set<Int> = [], delay: Duration? = nil) {
        self.shouldFail = shouldFail
        self.failingCalls = failingCalls
        self.delay = delay
    }

    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult {
        uploadCount += 1
        let call = uploadCount
        if let delay {
            try await Task.sleep(for: delay)
        }
        if shouldFail || failingCalls.contains(call) {
            throw MemoryMediaUploadError.finalizeFailed
        }
        return MemoryMediaUploadResult(memoryMediaID: memoryMediaID, mediaAssetID: UUID())
    }
}

extension MemoryTestMediaUploader: MemoryMediaUploading {}

nonisolated final class MemoryTestPhotoSaver: PhotoLibrarySaving, @unchecked Sendable {
    var result: PhotoLibrarySaveResult

    init(result: PhotoLibrarySaveResult) {
        self.result = result
    }

    func savePNG(_ data: Data) -> PhotoLibrarySaveResult {
        result
    }
}

/// A draft store backed by a throwaway defaults suite and temp directory, so tests never
/// touch the app's real drafts.
@MainActor
func makeIsolatedMemoryDraftStore() -> LocalMemoryDraftStore {
    let name = "MemoryDraftTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(name, isDirectory: true)
    return LocalMemoryDraftStore(defaults: defaults, directoryURL: directory)
}
