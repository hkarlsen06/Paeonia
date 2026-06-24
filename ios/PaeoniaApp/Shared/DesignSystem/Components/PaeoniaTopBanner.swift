import Foundation
import Observation
import SwiftUI

enum PaeoniaBannerStyle: Equatable {
    case error
}

struct PaeoniaBannerContent: Equatable, Identifiable {
    let id: UUID
    let style: PaeoniaBannerStyle
    let title: String?
    let message: String

    init(
        id: UUID = UUID(),
        style: PaeoniaBannerStyle,
        title: String? = nil,
        message: String
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
    }

    static func error(title: String? = nil, message: String) -> PaeoniaBannerContent {
        PaeoniaBannerContent(style: .error, title: title, message: message)
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
        }
    }

    func dismiss() {
        content = nil
    }
}

struct PaeoniaTopBanner: View {
    let content: PaeoniaBannerContent
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space12) {
            Image(systemName: iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

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

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.appBannerDismissButton))
        }
        .padding(.leading, PaeoniaSpacing.space16)
        .padding(.trailing, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space12)
        .frame(maxWidth: 430)
        .background(.paeoniaSurfacePressed)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: PaeoniaRadius.strokeDefault)
        }
        .shadow(color: .black.opacity(0.26), radius: 24, x: 0, y: 14)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch content.style {
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    private var accentColor: Color {
        switch content.style {
        case .error:
            .paeoniaError
        }
    }
}

private struct PaeoniaTopBannerModifier: ViewModifier {
    let center: PaeoniaBannerCenter

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let bannerContent = center.content {
                    PaeoniaTopBanner(
                        content: bannerContent,
                        onDismiss: center.dismiss
                    )
                    .padding(.horizontal, PaeoniaSpacing.space16)
                    .safeAreaPadding(.top, PaeoniaSpacing.space8)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                    .zIndex(1)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: center.content?.id)
    }
}

extension View {
    func paeoniaTopBanner(_ center: PaeoniaBannerCenter) -> some View {
        modifier(PaeoniaTopBannerModifier(center: center))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
