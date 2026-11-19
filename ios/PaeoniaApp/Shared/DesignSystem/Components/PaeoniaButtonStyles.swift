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
    private let isLoading: Bool
    private let isComplete: Bool

    init(isLoading: Bool = false, isComplete: Bool = false) {
        self.isLoading = isLoading
        self.isComplete = isComplete
    }

    func makeBody(configuration: Configuration) -> some View {
        PaeoniaFilledButton(
            configuration: configuration, isProminent: true, isLoading: isLoading, isComplete: isComplete
        )
    }
}

/// Same loading behavior as `PaeoniaPrimaryButtonStyle`.
struct PaeoniaSecondaryButtonStyle: ButtonStyle {
    private let isLoading: Bool

    init(isLoading: Bool = false) {
        self.isLoading = isLoading
    }

    func makeBody(configuration: Configuration) -> some View {
        PaeoniaFilledButton(configuration: configuration, isProminent: false, isLoading: isLoading, isComplete: false)
    }
}

/// The primary look while `isProminent`, otherwise the secondary one. For a button that
/// changes between the two in place: it stays one view, so its colors animate instead of
/// one button fading into another.
struct PaeoniaProminenceButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        PaeoniaFilledButton(configuration: configuration, isProminent: isProminent, isLoading: false, isComplete: false)
    }
}

private struct PaeoniaFilledButton: View {
    let configuration: ButtonStyleConfiguration
    let isProminent: Bool
    let isLoading: Bool
    let isComplete: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsEnabled: Bool { isEnabled || isLoading || isComplete }

    private var labelColor: Color {
        guard showsEnabled else { return .paeoniaTextTertiary }
        return isProminent ? .paeoniaTextInverse : .paeoniaTextPrimary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)

        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
            .foregroundStyle(labelColor)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: labelColor))
            .background(backgroundColor)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault)
                    .opacity(isProminent ? 0 : 1)
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && showsEnabled && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading && !isComplete)
    }

    private var backgroundColor: Color {
        guard showsEnabled else { return .paeoniaSurfaceDisabled }
        if isProminent {
            return configuration.isPressed ? .paeoniaAccentSecondary : .paeoniaAccentPrimary
        }
        return configuration.isPressed ? .paeoniaSurfacePressed : .paeoniaSurfacePrimary
    }
}

struct PaeoniaQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let isLoading: Bool

    /// Same loading behavior as `PaeoniaPrimaryButtonStyle`.
    init(isLoading: Bool = false) {
        self.isLoading = isLoading
    }

    private var showsEnabled: Bool { isEnabled || isLoading }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaeoniaTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space8)
            .frame(minWidth: PaeoniaSpacing.compactButtonHeight, minHeight: PaeoniaSpacing.compactButtonHeight)
            .foregroundStyle(.paeoniaTextSecondary)
            .modifier(PaeoniaButtonLoadingModifier(isLoading: isLoading, spinnerColor: .paeoniaTextSecondary))
            // Tertiary text is too close to secondary to read as off. A disabled
            // control needs no contrast, so it dims instead.
            .opacity(showsEnabled ? 1 : 0.4)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .animation(PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !showsEnabled {
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
            .scaleEffect(configuration.isPressed && showsEnabled && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : PaeoniaMotion.buttonPress, value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
    }
}

/// A round Liquid Glass button for an icon over content, such as a close button or a map
/// control. The glass reacts to touch the way the system `.glass` style does, but keeps a
/// fixed `face` size inside a tap target of at least 44 points, which `.glass` sizes from its
/// label instead.
struct PaeoniaGlassCircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var face: CGFloat = 32
    var glass: Glass = .regular

    func makeBody(configuration: Configuration) -> some View {
        let target = max(face, PaeoniaSpacing.compactButtonHeight)
        return configuration.label
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(width: face, height: face)
            .glassEffect(glass.interactive(), in: Circle())
            .opacity(isEnabled ? 1 : 0.4)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
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
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous))
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
