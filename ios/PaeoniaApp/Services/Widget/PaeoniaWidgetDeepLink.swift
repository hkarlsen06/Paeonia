import Foundation

nonisolated enum PaeoniaWidgetDeepLink: Equatable {
    case drawing

    static let scheme = "paeonia"
    static let host = "widget"
    static let drawingPathComponent = "drawing"

    static var drawingURL: URL {
        url(pathComponent: drawingPathComponent)
    }

    private static func url(pathComponent: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(pathComponent)"

        guard let url = components.url else {
            preconditionFailure("Invalid Paeonia widget drawing URL")
        }

        return url
    }

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host()?.lowercased() == Self.host
        else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        switch pathComponents {
        case [Self.drawingPathComponent]:
            self = .drawing
        default:
            return nil
        }
    }

    static func handles(_ url: URL) -> Bool {
        Self(url) != nil
    }
}
