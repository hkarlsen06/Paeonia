import Foundation
import UIKit
import WidgetKit

enum PaeoniaWidgetContent: Sendable {
    case placeholder
    case drawing(PaeoniaWidgetDrawingContent)
    case redacted
}

struct PaeoniaWidgetDrawingContent: Sendable {
    let image: UIImage
    let authorName: String?
    let savedAt: Date?
}

enum PaeoniaWidgetStore {
    static let appGroupIdentifier = "group.no.paeonia.app"

    private static let currentPayloadPath = "Widget/current.json"

    /// Shipped MVP privacy policy: only an explicitly normal, current-version
    /// payload with a safe preview path that decodes as an image may show the
    /// saved drawing.
    /// Missing, malformed, future-version, redacted, or incomplete state always
    /// degrades to a neutral placeholder; it never falls back to older content.
    static func loadContent(for family: WidgetFamily) -> PaeoniaWidgetContent {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return .placeholder
        }

        let payloadURL = containerURL.appendingPathComponent(currentPayloadPath)
        guard let payloadData = try? Data(contentsOf: payloadURL),
              let payload = try? payloadDecoder.decode(
                PaeoniaWidgetCurrentPayload.self,
                from: payloadData
              ),
              payload.schemaVersion == 1,
              payload.rendererVersion == 1
        else {
            return .placeholder
        }

        if payload.isRedacted || payload.privacyMode == .redacted {
            return .redacted
        }

        guard !payload.contentHash.isEmpty,
              let previewPath = payload.previewPath(for: family),
              isSafeRelativePath(previewPath)
        else {
            return .placeholder
        }

        // A missing or corrupt image must not fall back to the doodle while the
        // real author and time stay visible, so decode it before choosing content.
        let previewURL = containerURL.appendingPathComponent(previewPath)
        guard let image = UIImage(contentsOfFile: previewURL.path) else {
            return .placeholder
        }

        return .drawing(
            PaeoniaWidgetDrawingContent(
                image: image,
                authorName: payload.authorName,
                savedAt: payload.createdAt
            )
        )
    }

    private static var payloadDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

private struct PaeoniaWidgetCurrentPayload: Decodable {
    let schemaVersion: Int
    let authorName: String?
    let createdAt: Date?
    let renderedAt: Date?
    let rendererVersion: Int
    let privacyMode: PaeoniaWidgetPrivacyMode
    let isRedacted: Bool
    let contentHash: String
    let previews: [String: String]

    func previewPath(for family: WidgetFamily) -> String? {
        switch family {
        case .systemSmall, .systemMedium:
            // The medium widget draws the square at about the small widget's size.
            previews["systemSmall"]
        case .systemLarge:
            previews["systemLarge"]
        default:
            nil
        }
    }
}

private enum PaeoniaWidgetPrivacyMode: String, Decodable {
    case normal
    case redacted
}
