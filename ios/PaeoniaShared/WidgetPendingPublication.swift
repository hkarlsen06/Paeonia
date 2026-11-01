import Foundation

/// The app's uploader owns completion. A widget read cannot identify a send by matching its content.
nonisolated enum WidgetPendingPublication {
    static let storageKey = "paeonia.widgetCanvas.pendingUpload"

    static func canPublishRemoteDrawing(in defaults: UserDefaults?) -> Bool {
        defaults?.data(forKey: storageKey) == nil
    }

    static func keepsFirstDayDrawing(in defaults: UserDefaults?) -> Bool {
        guard let data = defaults?.data(forKey: storageKey),
              let marker = try? JSONDecoder().decode(FirstDayMarker.self, from: data) else { return false }
        return marker.isFirstDay
    }

    private struct FirstDayMarker: Decodable { let isFirstDay: Bool }
}
