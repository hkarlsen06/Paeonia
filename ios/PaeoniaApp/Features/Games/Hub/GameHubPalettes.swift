import SwiftUI
import UIKit

/// The picture a game card's palette comes from: the game's illustrated scene, or the
/// couple's latest content on a hub tile.
enum GameHubPaletteSource: Equatable {
    case illustration(GameKind)
    case content(GameChatPreview)
}

/// The palettes made so far this session, so a card that scrolls back into view gets its
/// colors at once, without reading its picture again. Views read it through Observation,
/// so a card updates when its palette is ready.
@Observable
final class GameHubPalettes {
    static let shared = GameHubPalettes()

    private var illustrations: [GameKind: GameHubPalette] = [:]
    /// The newest last. A preview is only `Equatable`, and a hub has at most one per game.
    private var contents: [(preview: GameChatPreview, palette: GameHubPalette)] = []
    private static let contentLimit = 32

    subscript(source: GameHubPaletteSource) -> GameHubPalette? {
        switch source {
        case .illustration(let kind): illustrations[kind]
        case .content(let preview): contents.last { $0.preview == preview }?.palette
        }
    }

    /// Reads the picture once and keeps its palette. `render` draws the card's picture as
    /// it shows, for every picture that is drawn in code.
    func load(_ source: GameHubPaletteSource, drawings: GameHistoryDrawings?, render: () -> CGImage?) async {
        guard self[source] == nil else { return }
        let images = await Self.images(of: source, drawings: drawings, render: render)
        guard !images.isEmpty, !Task.isCancelled else { return }
        let palette = await Self.palette(of: images)
        switch source {
        case .illustration(let kind):
            illustrations[kind] = palette
        case .content(let preview):
            contents.append((preview, palette))
            if contents.count > Self.contentLimit { contents.removeFirst() }
        }
    }

    @concurrent private static func palette(of images: [CGImage]) async -> GameHubPalette {
        GameHubPalette(images: images)
    }

    /// Drawings and photos load on their own, so their palette comes from the loaded images.
    private static func images(
        of source: GameHubPaletteSource, drawings: GameHistoryDrawings?, render: () -> CGImage?
    ) async -> [CGImage] {
        switch source {
        case .content(.drawing(let id)): await Self.drawings([id], from: drawings)
        case .content(.creature(let ids)): await Self.drawings(ids, from: drawings)
        case .content(.photo(let id)): await photo(id)
        case .illustration, .content: render().map { [$0] } ?? []
        }
    }

    private static func drawings(_ ids: [UUID], from drawings: GameHistoryDrawings?) async -> [CGImage] {
        guard let drawings else { return [] }
        var images: [CGImage] = []
        for id in ids {
            if let image = await drawings.thumbnail(for: id)?.cgImage { images.append(image) }
        }
        return images
    }

    private static func photo(_ id: UUID) async -> [CGImage] {
        guard let data = await MemoryMediaImageProviderFactory.shared?.imageData(for: id),
              let image = await MemoryImageDecoding.downsample(data, maxPixelSize: 64)?.cgImage
        else { return [] }
        return [image]
    }

    /// `view` drawn 96 pixels wide, enough to read its colors.
    static func render(_ view: some View, width: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 96 / width
        return renderer.cgImage
    }
}
