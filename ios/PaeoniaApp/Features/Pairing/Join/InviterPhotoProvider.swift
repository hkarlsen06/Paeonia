import Foundation

/// Loads the inviter's photo from the signed link in the invite preview, so
/// `PaeoniaProfilePhotoAvatar` can show it. Nothing is cached, because the person
/// has not joined yet and the link stops working after about 15 minutes.
nonisolated struct InviterPhotoProvider: ProfilePhotoImageProviding {
    let url: URL?
    var downloader: any ProfilePhotoDataDownloading = URLSessionProfilePhotoDataDownloader()

    func profilePhotoData(for _: UUID?) async -> Data? {
        guard let url,
              let download = try? await downloader.download(from: url),
              (200..<300).contains(download.statusCode ?? 200),
              ProfilePhotoImageService.isDecodableImage(download.data)
        else {
            return nil
        }

        return download.data
    }
}
