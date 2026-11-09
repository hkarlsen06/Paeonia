import AppIntents
import Foundation
import SwiftUI

struct PaeoniaBanner: View {
    let content: PaeoniaBannerContent
    let onDismiss: () -> Void
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            mainContent
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.appBannerDismissButton))
            .accessibilityIdentifier("app.banner.dismiss")
        }
        .foregroundStyle(.primary)
        .padding(.leading, PaeoniaSpacing.space16)
        .padding(.trailing, PaeoniaSpacing.space4)
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(minHeight: 56)
        .appEntityIdentifier(content.appEntityIdentifier)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(.appBannerDismissButton), onDismiss)
        .accessibilityAction(.escape, onDismiss)
    }

    @ViewBuilder
    private var mainContent: some View {
        if let onTap {
            Button(action: onTap) {
                mainContentLabel
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("app.banner.open")
        } else {
            mainContentLabel
        }
    }

    private var mainContentLabel: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            leadingIcon
            messageText
                .font(PaeoniaTypography.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var messageText: Text {
        if let title = content.titleText {
            Text(attributedMessage(title: title))
        } else {
            Text(verbatim: content.message)
        }
    }

    private func attributedMessage(title: String) -> AttributedString {
        var heading = AttributedString(title + ": ")
        heading.font = PaeoniaTypography.bodyEmphasis
        return heading + AttributedString(content.message)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let gameKind = content.gameKind {
            PaeoniaBannerGameIcon(kind: gameKind)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        } else if let avatar = content.avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Image(systemName: content.systemImage ?? iconName)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)
        }
    }

    private var iconName: String {
        switch content.style {
        case .error: "exclamationmark.circle"
        case .info: "bell.badge"
        }
    }
}

private struct PaeoniaBannerModifier: ViewModifier {
    let center: PaeoniaBannerCenter
    let isRoot: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hostID = UUID()

    private var banner: PaeoniaBannerContent? {
        center.isActiveHost(hostID) ? center.content : nil
    }

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(PaeoniaBannerBottomEdgeKey.self) { bottomEdge in
                GeometryReader { proxy in
                    let contentBottom = proxy.frame(in: .global).maxY
                    if let banner {
                        PaeoniaBannerPresentation(content: banner, center: center, onTap: onTap)
                            .id(banner.id)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                            .padding(.horizontal, PaeoniaSpacing.space8)
                            .padding(.bottom, PaeoniaSpacing.space8
                                + max(0, contentBottom - (bottomEdge ?? contentBottom)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .animation(bannerAnimation, value: banner?.id)
            .onAppear { center.registerHost(hostID, isRoot: isRoot) }
            .onDisappear { center.unregisterHost(hostID) }
    }

    private var bannerAnimation: Animation {
        reduceMotion
            ? PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)
            : .spring(response: 0.34, dampingFraction: 0.88)
    }
}

/// Keeps tap-to-open and downward swipe dismissal together for every banner host.
private struct PaeoniaBannerPresentation: View {
    let content: PaeoniaBannerContent
    let center: PaeoniaBannerCenter
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        PaeoniaBanner(
            content: content,
            onDismiss: { center.dismiss(id: content.id) },
            onTap: content.isTappable
                ? {
                    center.dismiss(id: content.id)
                    (content.action ?? onTap)()
                }
                : nil
        )
        .modifier(PaeoniaBannerSurface())
        .offset(y: dragOffset)
        .gesture(swipeDownToDismiss)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.86), value: dragOffset)
    }

    private var swipeDownToDismiss: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { dragOffset = max($0.translation.height, 0) }
            .onEnded { value in
                if value.translation.height > 28 {
                    center.dismiss(id: content.id)
                }
                dragOffset = 0
            }
    }
}

extension View {
    /// The frontmost screen or sheet draws the shared banner above its bottom safe area.
    func paeoniaBanner(
        _ center: PaeoniaBannerCenter,
        isRoot: Bool = false,
        onTap: @escaping () -> Void = {}
    ) -> some View {
        modifier(PaeoniaBannerModifier(center: center, isRoot: isRoot, onTap: onTap))
    }
}
