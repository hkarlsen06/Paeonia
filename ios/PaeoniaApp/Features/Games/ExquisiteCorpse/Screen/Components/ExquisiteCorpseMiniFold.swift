import SwiftUI

/// A small folded paper, 72 by 216 pt, for the waiting screen. It shows how far
/// the figure has come. Done parts are paper backs, the part being drawn has a
/// slow shimmer, and the parts after it are empty dashed outlines. It is only a
/// picture, so VoiceOver skips it. The title above says the same in words.
struct ExquisiteCorpseMiniFold: View {
    static let size = CGSize(width: 72, height: 216)

    /// How many parts are finished, from 0 to 2.
    let partsDone: Int
    /// The part being drawn right now. Nil when nobody is drawing.
    let openPart: ExquisiteCorpsePartKind?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.partCount, id: \.self) { index in
                panel(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private enum PanelState {
        case done
        case open
        case waiting
    }

    private func state(of index: Int) -> PanelState {
        if index < partsDone {
            .done
        } else if index == openPart?.rawValue {
            .open
        } else {
            .waiting
        }
    }

    @ViewBuilder
    private func panel(_ index: Int) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: index == 0 ? Self.corner : 0,
            bottomLeadingRadius: index == Self.partCount - 1 ? Self.corner : 0,
            bottomTrailingRadius: index == Self.partCount - 1 ? Self.corner : 0,
            topTrailingRadius: index == 0 ? Self.corner : 0,
            style: .continuous
        )
        switch state(of: index) {
        case .done:
            ExquisiteCorpsePaperBack()
                .clipShape(shape)
        case .open:
            ExquisiteCorpsePaperBack()
                .overlay { ExquisiteCorpseShimmer() }
                .clipShape(shape)
        case .waiting:
            // Inset, so two outlines in a row never share an edge.
            shape
                .inset(by: PaeoniaSpacing.space2)
                .strokeBorder(
                    .paeoniaTextTertiary,
                    style: StrokeStyle(lineWidth: PaeoniaRadius.strokeDefault, dash: [4, 3])
                )
        }
    }

    private static let partCount = 3
    private static let corner = PaeoniaRadius.radius12
}

/// A soft band of light that crosses the open part again and again. With Reduce
/// Motion the part keeps a still tint, so it still reads as the open one.
private struct ExquisiteCorpseShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    var body: some View {
        GeometryReader { proxy in
            let bandWidth = proxy.size.width * 0.6
            ZStack {
                Color.paeoniaAccentPrimary.opacity(0.14)
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .paeoniaTextPrimary.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: isSweeping ? proxy.size.width : -proxy.size.width)
                    .animation(Self.sweep, value: isSweeping)
                }
            }
        }
        .onAppear { isSweeping = true }
        .accessibilityHidden(true)
    }

    private static let sweep = PaeoniaMotion.standardCurve(duration: 2.4).repeatForever(autoreverses: false)
}

#if DEBUG
#Preview {
    HStack(alignment: .top, spacing: PaeoniaSpacing.space24) {
        ExquisiteCorpseMiniFold(partsDone: 0, openPart: .head)
        ExquisiteCorpseMiniFold(partsDone: 1, openPart: .body)
        ExquisiteCorpseMiniFold(partsDone: 2, openPart: .legs)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif
