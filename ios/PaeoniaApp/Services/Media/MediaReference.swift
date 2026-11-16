import Foundation

/// A stored photo or video to show. The kind travels with the asset id, because a video's
/// file loaded as a photo shows as a broken picture.
nonisolated enum MediaReference: Hashable, Sendable {
    case photo(UUID)
    case video(UUID, durationMs: Int?)

    var assetID: UUID {
        switch self {
        case let .photo(id), let .video(id, _): id
        }
    }

    var isVideo: Bool {
        if case .video = self { true } else { false }
    }

    var videoDurationMs: Int? {
        if case let .video(_, durationMs) = self { durationMs } else { nil }
    }

    /// For a tile too small for a video's length. Its badge then shows only the play glyph.
    var withoutDuration: MediaReference {
        if case let .video(id, _) = self { .video(id, durationMs: nil) } else { self }
    }
}
