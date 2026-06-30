import Foundation
import Observation
import SwiftUI
import UIKit

enum PaeoniaBannerStyle: Equatable {
    case error
    /// A neutral, non-error notice — used to surface a partner's update in-app
    /// while the app is open, in place of the system notification banner.
    case info
}

struct PaeoniaBannerContent: Equatable, Identifiable {
    let id: UUID
    let style: PaeoniaBannerStyle
    let title: String?
    let message: String
    /// Optional leading avatar (e.g. the partner's profile photo) shown in place
    /// of the style's icon.
    let imageData: Data?
    /// When true, tapping the banner invokes the host's tap handler (used to open
    /// the drawing screen from a partner-update notice).
    let isTappable: Bool

    init(
        id: UUID = UUID(),
        style: PaeoniaBannerStyle,
        title: String? = nil,
        message: String,
        imageData: Data? = nil,
        isTappable: Bool = false
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.imageData = imageData
        self.isTappable = isTappable
    }

    static func error(title: String? = nil, message: String) -> PaeoniaBannerContent {
        PaeoniaBannerContent(style: .error, title: title, message: message)
    }

    static func info(
        title: String? = nil,
        message: String,
        imageData: Data? = nil,
        isTappable: Bool = false
    ) -> PaeoniaBannerContent {
        PaeoniaBannerContent(
            style: .info,
            title: title,
            message: message,
            imageData: imageData,
            isTappable: isTappable
        )
    }
}

@MainActor
@Observable
final class PaeoniaBannerCenter {
    private(set) var content: PaeoniaBannerContent?

    func show(_ content: PaeoniaBannerContent) {
        self.content = content

        switch content.style {
        case .error:
            PaeoniaHaptics.validationError()
        case .info:
            PaeoniaHaptics.drawingSent()
        }
    }

    func dismiss() {
        content = nil
    }
}

struct PaeoniaTopBanner: View {
    let content: PaeoniaBannerContent
    let onDismiss: () -> Void
    var onTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space12) {
            mainContent
            dismissButton
        }
        .padding(.horizontal, PaeoniaSpacing.space16)
        .padding(.vertical, PaeoniaSpacing.space12)
        .frame(maxWidth: 430)
        // Liquid Glass so the banner reads as a translucent layer over the
        // content behind it, tinted by the style's accent.
        .glassEffect(
            .regular.tint(accentColor.opacity(0.16)),
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: PaeoniaRadius.strokeDefault)
        }
        .shadow(color: .black.opacity(0.26), radius: 24, x: 0, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(.appBannerDismissButton)) {
            onDismiss()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let onTap {
            Button(action: onTap) {
                mainContentLabel
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            mainContentLabel
        }
    }

    private var mainContentLabel: some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space12) {
            leadingIcon

            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                if let title = content.title?.nilIfBlank {
                    Text(verbatim: title)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                }

                Text(verbatim: content.message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let imageData = content.imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(accentColor.opacity(0.35), lineWidth: PaeoniaRadius.strokeDefault)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: 32, height: 32)
                .background(Color.paeoniaSurfacePrimary.opacity(0.28))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.appBannerDismissButton))
    }

    private var iconName: String {
        switch content.style {
        case .error:
            "exclamationmark.triangle.fill"
        case .info:
            "pencil.tip.crop.circle"
        }
    }

    private var accentColor: Color {
        switch content.style {
        case .error:
            .paeoniaError
        case .info:
            .paeoniaAccentPrimary
        }
    }
}

private struct PaeoniaTopBannerModifier: ViewModifier {
    let center: PaeoniaBannerCenter
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let bannerContent = center.content {
                    PaeoniaTopBannerPresentation(
                        content: bannerContent,
                        center: center,
                        onTap: onTap
                    )
                    .zIndex(1)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: center.content?.id)
    }
}

/// Presents a single banner with swipe-up-to-dismiss and (when tappable) tap-to-open.
private struct PaeoniaTopBannerPresentation: View {
    let content: PaeoniaBannerContent
    let center: PaeoniaBannerCenter
    let onTap: () -> Void

    /// Live upward drag, clamped to `<= 0`, so the banner follows the finger as
    /// the user swipes it up to dismiss.
    @State private var dragOffset: CGFloat = 0

    private static let dismissThreshold: CGFloat = 28

    var body: some View {
        tappableBanner
            .gesture(swipeUpToDismiss)
            .padding(.horizontal, PaeoniaSpacing.space16)
            .safeAreaPadding(.top, PaeoniaSpacing.space8)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.86), value: dragOffset)
    }

    @ViewBuilder
    private var tappableBanner: some View {
        PaeoniaTopBanner(
            content: content,
            onDismiss: center.dismiss,
            onTap: content.isTappable
                ? {
                    center.dismiss()
                    onTap()
                }
                : nil
        )
        .offset(y: dragOffset)
    }

    private var swipeUpToDismiss: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = min(value.translation.height, 0)
            }
            .onEnded { value in
                if value.translation.height < -Self.dismissThreshold {
                    center.dismiss()
                }
                dragOffset = 0
            }
    }
}

extension View {
    func paeoniaTopBanner(
        _ center: PaeoniaBannerCenter,
        onTap: @escaping () -> Void = {}
    ) -> some View {
        modifier(PaeoniaTopBannerModifier(center: center, onTap: onTap))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
