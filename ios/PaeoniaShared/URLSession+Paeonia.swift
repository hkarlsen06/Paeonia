import Foundation

extension URLSession {
    /// The session for every request the app and its extensions make. Responses from
    /// the backend and media downloads hold the couple's private content, and
    /// `URLSession.shared` would keep them in the system web cache on disk, where
    /// deleting content or signing out cannot reach them. This session keeps no cache,
    /// cookies or credentials on disk. The app keeps the copies it wants in its own
    /// caches, which the privacy purge clears.
    nonisolated static let paeonia: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}
