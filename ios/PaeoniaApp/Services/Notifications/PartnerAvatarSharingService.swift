import Foundation

/// Copies the partner's avatar into the App Group so the Notification Service
/// Extension can show it on the widget update alert (a communication
/// notification). The extension cannot reach the network in time, so the image
/// is pre-staged here while the app is paired and cleared when access ends.
nonisolated protocol PartnerAvatarSharing: Sendable {
    func cachePartnerAvatar(assetID: UUID?) async
    func clear() async
}

actor PartnerAvatarSharingService: PartnerAvatarSharing {
    private let imageProvider: any ProfilePhotoImageProviding
    private let appGroupContainerURL: URL?

    init(
        imageProvider: any ProfilePhotoImageProviding,
        appGroupContainerURL: URL? = PaeoniaAppGroup.containerURL
    ) {
        self.imageProvider = imageProvider
        self.appGroupContainerURL = appGroupContainerURL
    }

    func cachePartnerAvatar(assetID: UUID?) async {
        guard let assetID, let fileURL = avatarFileURL else {
            return
        }

        guard let data = await imageProvider.profilePhotoData(for: assetID) else {
            return
        }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    // Actor isolation satisfies the protocol's `async` requirement without the
    // keyword; the body has nothing to await.
    func clear() {
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
    static func makeDefault() -> (any PartnerAvatarSharing)? {
        guard let imageProvider = ProfilePhotoImageProviderFactory.shared else {
            return nil
        }
        return PartnerAvatarSharingService(imageProvider: imageProvider)
    }
}
