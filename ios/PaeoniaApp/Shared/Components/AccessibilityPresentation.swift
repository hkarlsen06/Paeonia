import SwiftUI

/// Optional visible tools, separate from the app's always-on accessibility semantics.
@propertyWrapper
struct AccessibilityPresentation: DynamicProperty {
    enum Kind { case controls, media }

    private let kind: Kind
    @AppStorage("accessibility.alwaysShowControls") private var alwaysShowControls = false
    @AppStorage("accessibility.alwaysShowMediaAlternatives") private var alwaysShowMedia = false
    @Environment(\.accessibilityEnabled) private var assistiveTechnologyEnabled

    init(_ kind: Kind) { self.kind = kind }

    var wrappedValue: Bool {
        assistiveTechnologyEnabled || projectedValue.wrappedValue
    }

    /// Settings edits the saved Always choice. Automatic also follows assistive technology.
    var projectedValue: Binding<Bool> {
        switch kind {
        case .controls: $alwaysShowControls
        case .media: $alwaysShowMedia
        }
    }
}
