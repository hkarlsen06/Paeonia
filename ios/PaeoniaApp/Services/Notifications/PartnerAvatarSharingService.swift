import Foundation

/// Copies the partner's avatar into the App Group so the Notification Service
/// Extension can show it on the widget update alert (a communication
/// notification). The extension cannot reach the network in time, so the image
/// is pre-staged here while the app is paired and cleared when access ends.
nonisolated protocol PartnerAvatarSharing: Sendable {
    /// Stages the partner's photo, or removes the staged one when `assetID` is nil
    /// because the partner has no photo. Returns false when the photo could not be
    /// downloaded, so the caller can try again.
    @discardableResult
    func cachePartnerAvatar(assetID: UUID?) async -> Bool
    func clear() async
}

actor PartnerAvatarSharingService: PartnerAvatarSharing {
    private let imageProvider: any ProfilePhotoImageProviding
    private let appGroupContainerURL: URL?
    /// Changes with every request and with `clear()`. Only the newest request
    /// writes, so a download that finishes late never brings back a photo that
    /// was removed, replaced, or cleared by a privacy purge.
    private var generation: UInt64 = 0

    init(
        imageProvider: any ProfilePhotoImageProviding,
        appGroupContainerURL: URL? = PaeoniaAppGroup.containerURL
    ) {
        self.imageProvider = imageProvider
        self.appGroupContainerURL = appGroupContainerURL
    }

    @discardableResult
    func cachePartnerAvatar(assetID: UUID?) async -> Bool {
        guard let fileURL = avatarFileURL else {
            return true
        }
        generation &+= 1
        let requestedGeneration = generation
        // A removed photo must not keep showing on alerts and banners.
        guard let assetID else {
            try? FileManager.default.removeItem(at: fileURL)
            return true
        }

        guard let data = await imageProvider.profilePhotoData(for: assetID) else {
            return false
        }
        // A newer request or a purge took over while this one downloaded.
        guard requestedGeneration == generation, !Task.isCancelled else {
            return true
        }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
        return true
    }

    // Actor isolation satisfies the protocol's `async` requirement without the
    // keyword; the body has nothing to await.
    func clear() {
        generation &+= 1
        guard let fileURL = avatarFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private var avatarFileURL: URL? {
        appGroupContainerURL?.appendingPathComponent(PaeoniaAppGroup.communicationPartnerAvatarPath)
    }
}

nonisolated enum PartnerAvatarSharingServiceFactory {
    static let shared: (any PartnerAvatarSharing)? = makeLive()

    static func makeDefault() -> (any PartnerAvatarSharing)? {
        shared
    }

    private static func makeLive() -> (any PartnerAvatarSharing)? {
        guard let imageProvider = ProfilePhotoImageProviderFactory.shared else {
            return nil
        }
        return PartnerAvatarSharingService(imageProvider: imageProvider)
    }
}
