import Foundation

/// Adopted by launch-adjacent screens whose first visible frame depends on
/// async data. Keep the launch/loading screen visible until this becomes true.
@MainActor
protocol PresentationReadinessProviding {
    var isPresentationReady: Bool { get }
}
