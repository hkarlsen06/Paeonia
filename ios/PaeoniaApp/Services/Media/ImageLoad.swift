import UIKit

/// A picture a view loads for one key, such as a media asset ID. The result keeps
/// its key, so a view that moves to another picture shows neither the old image nor
/// the old failure while the new one loads.
enum ImageLoad<Key: Equatable> {
    case loading
    case loaded(Key, UIImage)
    case failed(Key)

    init(_ image: UIImage?, for key: Key) {
        self = image.map { .loaded(key, $0) } ?? .failed(key)
    }

    func image(for key: Key) -> UIImage? {
        guard case let .loaded(loadedKey, image) = self, loadedKey == key else { return nil }
        return image
    }

    func hasFailed(for key: Key) -> Bool {
        guard case let .failed(failedKey) = self else { return false }
        return failedKey == key
    }
}
