import Foundation
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct ProfileEditorViewModelTests {
    /// Picking photo A (slow, from iCloud) and then photo B used to let A finish
    /// last and open its crop sheet over B's.
    @Test func slowerFirstPickNeverReplacesNewerPick() async throws {
        let editor = ProfileEditorViewModel()
        let slowLoad = HeldPhotoLoad()

        editor.pickPhoto { await slowLoad.load() }
        await waitUntil { await slowLoad.isWaiting }

        let secondImage = Self.imageData(size: CGSize(width: 2, height: 3))
        editor.pickPhoto { secondImage }
        await waitUntil { editor.cropRequest != nil }

        let secondRequest = try #require(editor.cropRequest)
        #expect(secondRequest.image.size == CGSize(width: 2, height: 3))

        await slowLoad.finish(with: Self.imageData(size: CGSize(width: 5, height: 5)))
        try await Task.sleep(for: .milliseconds(50))

        #expect(editor.cropRequest?.id == secondRequest.id)
        #expect(!editor.isLoadingPhoto)
    }

    /// With a saved photo and a staged replacement, the trash button used to drop
    /// the replacement and also mark the saved photo for removal.
    @Test func removingStagedPhotoKeepsSavedPhoto() async {
        let savedPhoto = UUID()
        let editor = ProfileEditorViewModel()
        editor.updateSavedProfile(name: "Alex", customPhotoAssetID: savedPhoto, providerPhotoAssetID: nil)
        await editor.applyCroppedPhoto(Self.image())

        editor.removePhoto()

        #expect(editor.draft.photoUpdate == .unchanged)
        #expect(editor.draft.previewPhotoAssetID == savedPhoto)

        editor.removePhoto()

        #expect(editor.draft.photoUpdate == .remove)
    }

    @Test func failedSaveKeepsEditsAndReportsFailure() async {
        let editor = ProfileEditorViewModel()
        editor.updateSavedProfile(name: "Alex", customPhotoAssetID: nil, providerPhotoAssetID: nil)
        editor.setName("Sam")

        await editor.save { _, _ in false }

        #expect(editor.event == .saveFailed)
        #expect(editor.draft.name == "Sam")
        #expect(editor.draft.hasChanges)
        #expect(editor.completedSaveCount == 0)
    }

    /// A second tap while the first save runs must not send the profile twice,
    /// and the name cannot change under the running save.
    @Test func saveIgnoresSecondTapAndEditsWhileSaving() async {
        let editor = ProfileEditorViewModel()
        editor.updateSavedProfile(name: "Alex", customPhotoAssetID: nil, providerPhotoAssetID: nil)
        editor.setName("Sam")
        let gate = HeldSave()

        let firstSave = Task { await editor.save { name, _ in await gate.save(name) } }
        await waitUntil { await gate.callCount == 1 }

        await editor.save { name, _ in await gate.save(name) }
        editor.setName("Robin")
        editor.pickPhoto { Self.imageData(size: CGSize(width: 1, height: 1)) }

        #expect(editor.isSaving)
        #expect(await gate.callCount == 1)
        #expect(editor.draft.name == "Sam")
        #expect(!editor.isLoadingPhoto)

        await gate.finish(returning: true)
        await firstSave.value

        #expect(await gate.savedNames == ["Sam"])
        #expect(!editor.isSaving)
    }

    /// Encoding the cropped photo takes a moment. Save used to stay enabled then,
    /// so a save could miss the photo and its success would wipe it, and a
    /// Cancel during the encode was undone when the encode finished.
    @Test func cropEncodeBlocksSaveAndLosesToDiscard() async {
        let encode = HeldEncode()
        let editor = ProfileEditorViewModel { _ in await encode.encode() }
        editor.updateSavedProfile(name: "Alex", customPhotoAssetID: nil, providerPhotoAssetID: nil)
        editor.setName("Sam")

        let applying = Task { await editor.applyCroppedPhoto(Self.image()) }
        await waitUntil { await encode.isWaiting }

        #expect(editor.isLoadingPhoto)
        #expect(!editor.canSave)

        editor.discard()
        await encode.finish(with: Self.imageData(size: CGSize(width: 1, height: 1)))
        await applying.value

        #expect(editor.stagedPhotoData == nil)
        #expect(!editor.draft.hasChanges)
        #expect(!editor.isLoadingPhoto)
    }

    @Test func discardDropsEditsAndPendingPhotoLoad() async {
        let editor = ProfileEditorViewModel()
        editor.updateSavedProfile(name: "Alex", customPhotoAssetID: nil, providerPhotoAssetID: nil)
        editor.setName("Sam")
        let slowLoad = HeldPhotoLoad()
        editor.pickPhoto { await slowLoad.load() }
        await waitUntil { await slowLoad.isWaiting }

        editor.discard()
        await slowLoad.finish(with: Self.imageData(size: CGSize(width: 1, height: 1)))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!editor.draft.hasChanges)
        #expect(editor.cropRequest == nil)
        #expect(!editor.isLoadingPhoto)
    }

    private static func image(size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func imageData(size: CGSize) -> Data {
        image(size: size).pngData() ?? Data()
    }
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// A photo load that waits until the test lets it finish.
private actor HeldPhotoLoad {
    private var continuation: CheckedContinuation<Data?, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func load() async -> Data? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(with data: Data?) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

/// A profile save that waits until the test lets it finish.
private actor HeldSave {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var callCount = 0
    private(set) var savedNames = [String]()

    func save(_ name: String) async -> Bool {
        callCount += 1
        savedNames.append(name)
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(returning result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// A photo encode that waits until the test lets it finish.
private actor HeldEncode {
    private var continuation: CheckedContinuation<Data?, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func encode() async -> Data? {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(with data: Data?) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}
