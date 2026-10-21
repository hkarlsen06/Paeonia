import SwiftUI

/// The frame every shared card sits in: the deep plum of the app, a soft petal
/// glow, the content, an optional title and subtitle, and a small Paeonia
/// wordmark at the bottom.
struct PaeoniaShareCardFrame<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            content
            if title != nil || subtitle != nil {
                VStack(spacing: PaeoniaSpacing.space4) {
                    if let title {
                        Text(verbatim: title)
                            .font(PaeoniaTypography.collectionTitle)
                            .foregroundStyle(.paeoniaTextPrimary)
                    }
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
                .multilineTextAlignment(.center)
            }
            PaeoniaWordmark(size: 15)
                .opacity(0.7)
        }
        .padding(PaeoniaShareRenderer.cardMargin)
        .frame(width: PaeoniaShareRenderer.cardWidth)
        .background {
            ZStack {
                Color.paeoniaBackgroundSecondary
                RadialGradient(
                    colors: [.paeoniaAccentPrimary.opacity(0.16), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: PaeoniaShareRenderer.cardWidth
                )
            }
        }
    }
}

/// The plum canvas a drawing was made on: a rounded square with the ink on top.
/// It looks like the drawing square in the app.
struct PaeoniaShareCanvas: View {
    let ink: UIImage
    var side: CGFloat = PaeoniaShareRenderer.contentWidth

    var body: some View {
        Image(uiImage: ink)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .background(.paeoniaBackgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeEmphasis)
            }
            .accessibilityHidden(true)
    }
}

/// Makes the shared picture of a single drawing: the ink on its plum canvas in
/// the frame.
enum PaeoniaShareCards {
    static func drawing(ink: UIImage, title: String? = nil, subtitle: String? = nil) -> PaeoniaShareImage? {
        PaeoniaShareRenderer.png(
            PaeoniaShareCardFrame(title: title, subtitle: subtitle) {
                PaeoniaShareCanvas(ink: ink)
            }
        )
    }
}
