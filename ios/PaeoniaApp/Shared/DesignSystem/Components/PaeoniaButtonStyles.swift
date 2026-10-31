import SwiftUI

/// Keeps the label in the layout but hidden while `isLoading`, so the button
/// does not change size, and centers a spinner over it.
private struct PaeoniaButtonLoadingModifier: ViewModifier {
    let isLoading: Bool
    let spinnerColor: Color

    func body(content: Content) -> some View {
        content
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(spinnerColor)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(isLoading ? String(localized: .commonLoading) : "")
    }
}

/// While `isLoading`, the button keeps its enabled look, shows a spinner, and
/// ignores taps. Pair it with the screen's own guard against double submits.
struct PaeoniaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isLoading: Bool
    private let isComplete: Bool

    init(isLoading: Bool = false, isComplete: Bool = false) {
        self.isLoading = isLoading
        self.isComplete = isComplete
    }

    private var showsEnabled: Bool { isEnabled || isLoading || isComplete }
    private var labelColor: Color { showsEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .foregroundStyle(labelColor)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: labelColor))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && showsEnabled && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading && !isComplete)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !showsEnabled {
            return .paeoniaSurfaceDisabled
        }

        return isPressed ? .paeoniaAccentSecondary : .paeoniaAccentPrimary
    }
}

/// Same loading behavior as `PaeoniaPrimaryButtonStyle`.
struct PaeoniaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isLoading: Bool

    init(isLoading: Bool = false) {
        self.isLoading = isLoading
    }

    private var showsEnabled: Bool { isEnabled || isLoading }
    private var labelColor: Color { showsEnabled ? .paeoniaTextPrimary : .paeoniaTextTertiary }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .foregroundStyle(labelColor)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: labelColor))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && showsEnabled && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !showsEnabled {
            return .paeoniaSurfaceDisabled
        }

        return isPressed ? .paeoniaSurfacePressed : .paeoniaSurfacePrimary
    }
}

struct PaeoniaQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .frame(minWidth: PaeoniaSpacing.compactButtonHeight, minHeight: PaeoniaSpacing.compactButtonHeight)
            .foregroundStyle(isEnabled ? .paeoniaTextSecondary : .paeoniaTextTertiary)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return .clear
        }

        return isPressed ? .paeoniaSurfacePressed : .clear
    }
}

/// A compact circular action, with a 36-point face inside a 44-point tap target.
struct PaeoniaCircularButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isProminent = true
    var tint: Color = .paeoniaAccentPrimary
    var isLoading = false

    private var showsEnabled: Bool { isEnabled || isLoading }
    private var labelColor: Color {
        showsEnabled ? (isProminent ? .paeoniaTextInverse : tint) : .paeoniaTextTertiary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(labelColor)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: labelColor))
            .frame(width: 36, height: 36)
            .background(
                showsEnabled ? (isProminent ? tint : tint.opacity(0.16)) : .paeoniaSurfaceDisabled,
                in: Circle()
            )
            .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && showsEnabled && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
    }
}

struct PaeoniaDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .foregroundStyle(isEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return .paeoniaSurfaceDisabled
        }

        return isPressed ? .paeoniaErrorPressed : .paeoniaError
    }
}
