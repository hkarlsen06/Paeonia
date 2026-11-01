import SwiftUI
import UIKit

/// Optional visible tools, separate from the app's always-on accessibility semantics.
@propertyWrapper
struct AccessibilityPresentation: DynamicProperty {
    enum Kind { case controls, media }

    private let kind: Kind
    @AppStorage("accessibility.alwaysShowControls") private var alwaysShowControls = false
    @AppStorage("accessibility.alwaysShowMediaAlternatives") private var alwaysShowMedia = false
    @Environment(\.accessibilityEnabled) private var assistiveTechnologyEnabled
    #if DEBUG
    @Environment(\.scenarioAssistiveTechnologyEnabled) private var simulatedEnabled
    #endif

    init(_ kind: Kind) { self.kind = kind }

    var wrappedValue: Bool {
        #if DEBUG
        let automatic = simulatedEnabled ?? assistiveTechnologyEnabled
        #else
        let automatic = assistiveTechnologyEnabled
        #endif
        return automatic || projectedValue.wrappedValue
    }

    /// Settings edits the saved Always choice. Automatic also follows assistive technology.
    var projectedValue: Binding<Bool> {
        switch kind {
        case .controls: $alwaysShowControls
        case .media: $alwaysShowMedia
        }
    }
}

#if DEBUG
extension EnvironmentValues {
    /// Only Paeonia's optional presentation reads this fixture. Native accessibility stays active.
    @Entry var scenarioAssistiveTechnologyEnabled: Bool? = nil
}
#endif

/// The app's High contrast switch acts like iOS Increase Contrast for Paeonia only,
/// so asset colors pick their high contrast variants and views read `colorSchemeContrast`.
struct PaeoniaContrastPreference: ViewModifier {
    static let storageKey = "accessibility.highContrast"
    @AppStorage(Self.storageKey) private var highContrast = false

    func body(content: Content) -> some View {
        content.onChange(of: highContrast, initial: true) { _, isOn in
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                if isOn {
                    scene.traitOverrides.accessibilityContrast = .high
                } else {
                    scene.traitOverrides.remove(UITraitAccessibilityContrast.self)
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Board pieces differ by color alone unless the person asked for more than color.
    var showsBoardOwnerSymbols: Bool {
        accessibilityDifferentiateWithoutColor || colorSchemeContrast == .increased
    }
}
