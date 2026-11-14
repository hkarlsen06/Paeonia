import AppIntents
import Foundation
import SwiftUI

struct PaeoniaBanner: View {
    let content: PaeoniaBannerContent
    let onDismiss: () -> Void
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            mainContent
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.appBannerDismissButton))
            .accessibilityIdentifier("app.banner.dismiss")
        }
        .foregroundStyle(.primary)
        .padding(.leading, PaeoniaSpacing.space12)
        .padding(.trailing, PaeoniaSpacing.space4)
        .padding(.vertical, PaeoniaSpacing.space8)
        .frame(minHeight: 60)
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
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                if let title = content.titleText {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(verbatim: content.message)
                    .font(.subheadline)
                    // A partner's long message shows as a preview. The whole
                    // message is in the chat the banner opens. Errors are ours and short.
                    .lineLimit(content.style == .info ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let gameKind = content.gameKind {
            PaeoniaBannerGameIcon(kind: gameKind)
        } else if let avatar = content.avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Image(systemName: content.systemImage ?? iconName)
                .font(.system(size: 20, weight: .medium))
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
                            .frame(maxWidth: 560)
                            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
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

/// A tap or a swipe up opens a banner that opens something, and a swipe down dismisses
/// any banner, in every banner host.
private struct PaeoniaBannerPresentation: View {
    let content: PaeoniaBannerContent
    let center: PaeoniaBannerCenter
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        PaeoniaBanner(content: content, onDismiss: { center.dismiss(id: content.id) }, onTap: open)
        .modifier(PaeoniaBannerSurface())
        .offset(y: dragOffset)
        .gesture(swipe)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.86), value: dragOffset)
    }

    private var open: (() -> Void)? {
        guard content.isTappable else { return nil }
        return {
            center.dismiss(id: content.id)
            (content.action ?? onTap)()
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let moved = value.translation.height
                // Up only a little, as a pull, and only when there is something to open.
                dragOffset = moved >= 0 ? moved : open == nil ? 0 : moved / 3
            }
            .onEnded { value in
                if value.translation.height > 28 {
                    center.dismiss(id: content.id)
                } else if let open, value.translation.height < -28 || value.predictedEndTranslation.height < -80 {
                    open()
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
