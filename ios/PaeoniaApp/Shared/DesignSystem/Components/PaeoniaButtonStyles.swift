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
    private let isLoading: Bool

    init(isLoading: Bool = false) {
        self.isLoading = isLoading
    }

    private var showsEnabled: Bool { isEnabled || isLoading }
    private var labelColor: Color { showsEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

        return configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .foregroundStyle(labelColor)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: labelColor))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && showsEnabled ? 0.98 : 1)
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
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
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .foregroundStyle(labelColor)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: labelColor))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && showsEnabled ? 0.98 : 1)
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
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
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .padding(.horizontal, PaeoniaSpacing.space12)
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

struct PaeoniaDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .foregroundStyle(isEnabled ? .paeoniaTextInverse : .paeoniaTextTertiary)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return .paeoniaSurfaceDisabled
        }

        return isPressed ? .paeoniaErrorPressed : .paeoniaError
    }
}
