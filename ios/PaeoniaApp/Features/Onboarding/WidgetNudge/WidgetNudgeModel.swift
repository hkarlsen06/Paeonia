import Foundation
import Observation
// WidgetCenter is not marked Sendable, but reading its configurations is safe.
@preconcurrency import WidgetKit

/// The kinds of the widgets the person has on their Home Screen and Lock Screen.
/// Injected so tests can say which widgets are installed.
nonisolated protocol WidgetConfigurationProviding: Sendable {
    func installedWidgetKinds() async throws -> [String]
}

nonisolated struct WidgetCenterConfigurations: WidgetConfigurationProviding {
    func installedWidgetKinds() async throws -> [String] {
        try await WidgetCenter.shared.currentConfigurations().map(\.kind)
    }
}

/// Watches for the Paeonia drawing widget while the onboarding step asks the person
/// to add it. The step checks when it appears and each time the app comes back to
/// the front, since adding a widget means leaving the app.
@MainActor
@Observable
final class WidgetNudgeModel {
    /// True once the drawing widget was found. It stays true.
    private(set) var isAdded = false

    private let configurations: any WidgetConfigurationProviding
    private let recheckDelay: Duration

    /// `recheckDelay` is the wait before the second check after the app comes back.
    init(
        configurations: any WidgetConfigurationProviding = WidgetCenterConfigurations(),
        recheckDelay: Duration = .seconds(1.5)
    ) {
        self.configurations = configurations
        self.recheckDelay = recheckDelay
    }

    /// True when the drawing widget is on the Home Screen. A caller can use it to
    /// skip the step for someone who already has the widget.
    static func isWidgetInstalled(
        configurations: any WidgetConfigurationProviding = WidgetCenterConfigurations()
    ) async -> Bool {
        // A failed read counts as not installed. The step then just keeps asking.
        let kinds = (try? await configurations.installedWidgetKinds()) ?? []
        return kinds.contains(PaeoniaAppGroup.widgetKind)
    }

    /// Checks once. Returns true only for the check that first finds the widget, so
    /// the step celebrates once even when two checks overlap.
    @discardableResult
    func check() async -> Bool {
        guard !isAdded else {
            return false
        }
        let found = await Self.isWidgetInstalled(configurations: configurations)
        guard found, !isAdded else {
            return false
        }
        isAdded = true
        return true
    }

    /// Checks after the app comes back to the front, then once more after a short
    /// wait, because WidgetKit may not list a widget the moment it was added.
    @discardableResult
    func checkAfterReturning() async -> Bool {
        if await check() {
            return true
        }
        guard !isAdded else {
            return false
        }
        try? await Task.sleep(for: recheckDelay)
        guard !Task.isCancelled else {
            return false
        }
        return await check()
    }
}
