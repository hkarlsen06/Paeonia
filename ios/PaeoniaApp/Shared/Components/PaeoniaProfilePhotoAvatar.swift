import SwiftUI
import UIKit

struct PaeoniaProfilePhotoAvatar: View {
    let mediaAssetID: UUID?
    let name: String
    let tint: Color
    let size: CGFloat
    private let profilePhotoProvider: any ProfilePhotoImageProviding

    @State private var profileImage: UIImage?
    /// The asset `profileImage` was loaded for. A new asset id clears the old photo
    /// so it never shows under someone else's name; reloading the same id keeps it.
    @State private var loadedAssetID: UUID?

    /// Photos bigger than this decode off the main actor so lists keep scrolling.
    private static let backgroundDecodeThreshold = 200_000

    init(
        mediaAssetID: UUID?,
        name: String,
        tint: Color,
        size: CGFloat,
        profilePhotoProvider: (any ProfilePhotoImageProviding)? = nil
    ) {
        self.mediaAssetID = mediaAssetID
        self.name = name
        self.tint = tint
        self.size = size
        self.profilePhotoProvider = profilePhotoProvider
            ?? ProfilePhotoImageProviderFactory.shared
            ?? EmptyProfilePhotoImageProvider()
        // A photo shown before is in the first frame, with no initials in between.
        if let cached = PaeoniaImageMemoryCache.image(for: mediaAssetID) {
            _profileImage = State(initialValue: cached)
            _loadedAssetID = State(initialValue: mediaAssetID)
        }
    }

    var body: some View {
        ZStack {
            // Opaque backing so initials-only avatars don't let a map or photo show through.
            Circle()
                .fill(.paeoniaBackgroundSecondary)
                .overlay(Circle().fill(tint.opacity(0.18)))

            if let profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                initials
            }

            Circle()
                .strokeBorder(tint.opacity(0.82), lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        // The fetched photo fades in over the initials instead of snapping the
        // moment its download lands (cache hits resolve before the first frame,
        // so the common case still shows the photo immediately).
        .animation(PaeoniaMotion.stateChange, value: profileImage != nil)
        .accessibilityLabel(Text(name))
        .task(id: mediaAssetID) { await loadProfileImage() }
    }

    private var initials: some View {
        Text(Self.initials(for: name))
            .font(.system(size: size * 0.33, weight: .semibold, design: .rounded))
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func loadProfileImage() async {
        if loadedAssetID != mediaAssetID {
            profileImage = nil
            loadedAssetID = nil
        }

        let load = { () async -> UIImage? in
            guard let data = await profilePhotoProvider.profilePhotoData(for: mediaAssetID) else {
                return nil
            }
            return await Self.decode(data)
        }
        // Initials show while a failed download is tried again. Without an asset id
        // only a custom provider has a photo, such as an invite preview's link, and
        // it gets one try.
        let image = if mediaAssetID == nil {
            await load()
        } else {
            await ProfilePhotoRetry.load(load)
        }
        guard let image, !Task.isCancelled else {
            return
        }

        profileImage = image
        loadedAssetID = mediaAssetID
        if let mediaAssetID {
            PaeoniaImageMemoryCache.store(image, for: mediaAssetID)
        }
    }

    private static func decode(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        guard data.count > backgroundDecodeThreshold else {
            return image
        }

        return await image.byPreparingForDisplay() ?? image
    }

    static func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        if parts.isEmpty {
            return "?"
        }

        return parts.map { String($0).uppercased() }.joined()
    }
}

private struct EmptyProfilePhotoImageProvider: ProfilePhotoImageProviding {
    func profilePhotoData(for mediaAssetID: UUID?) async -> Data? {
        await Task.yield()
        return nil
    }
}
