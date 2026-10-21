import Foundation

/// Runs a profile photo load again after it fails, waiting longer each time, for as
/// long as the calling task runs. A view's `.task(id:)` is cancelled when the view
/// goes away or shows another photo, and that ends the retries.
///
/// `ProfilePhotoImageService` remembers a failure that retrying will not fix, such as
/// a deleted photo, for a minute. A retry inside that minute sends no request.
enum ProfilePhotoRetry {
    static let defaultDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)]

    /// The first value `attempt` returns, or nil once the task is cancelled.
    /// `onFailure` runs after each failed attempt.
    static func load<Value>(
        delays: [Duration] = defaultDelays,
        onFailure: () -> Void = {},
        _ attempt: () async -> Value?
    ) async -> Value? {
        var failures = 0
        while !Task.isCancelled {
            if let value = await attempt() {
                return value
            }
            guard !Task.isCancelled else {
                return nil
            }

            onFailure()
            let delay = delays.isEmpty ? .zero : delays[min(failures, delays.count - 1)]
            failures += 1
            do {
                try await Task.sleep(for: delay)
            } catch {
                return nil
            }
        }
        return nil
    }
}
