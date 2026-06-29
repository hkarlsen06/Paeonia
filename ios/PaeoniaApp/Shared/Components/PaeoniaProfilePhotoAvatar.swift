import SwiftUI
import UIKit

struct PaeoniaProfilePhotoAvatar: View {
    let mediaAssetID: UUID?
    let name: String
    let tint: Color
    let size: CGFloat
    private let profilePhotoProvider: any ProfilePhotoImageProviding

    @State private var imageData: Data?

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
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))

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
        .accessibilityLabel(Text(name))
        .task(id: mediaAssetID) {
            imageData = await profilePhotoProvider.profilePhotoData(for: mediaAssetID)
        }
    }

    private var initials: some View {
        Text(Self.initials(for: name))
            .font(.system(size: size * 0.33, weight: .semibold, design: .rounded))
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var profileImage: UIImage? {
        guard let imageData else {
            return nil
        }

        return UIImage(data: imageData)
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
