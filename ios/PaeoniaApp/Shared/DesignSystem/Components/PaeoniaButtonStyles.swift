import SwiftUI

struct PaeoniaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .foregroundStyle(isEnabled ? .paeoniaTextInverse : .paeoniaTextSecondary)
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

        return isPressed ? .paeoniaAccentSecondary : .paeoniaAccentPrimary
    }
}

struct PaeoniaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .foregroundStyle(isEnabled ? .paeoniaTextPrimary : .paeoniaTextTertiary)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
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

/// A quiet text button for destructive actions that must stay visually
/// subordinate to the actions above them (for example "Delete account" under
/// "Log out"). Unlike `PaeoniaQuietButtonStyle`, the label reads in the error
/// color so the consequence is visible before tapping.
struct PaeoniaQuietDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .foregroundStyle(isEnabled ? .paeoniaError : .paeoniaTextTertiary)
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
            .foregroundStyle(isEnabled ? .paeoniaTextInverse : .paeoniaTextSecondary)
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

        return isPressed ? .paeoniaWarning : .paeoniaError
    }
}
