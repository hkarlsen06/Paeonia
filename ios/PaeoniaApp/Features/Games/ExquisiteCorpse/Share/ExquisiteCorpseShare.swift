import PencilKit
import SwiftUI

extension ExquisiteCorpseRevealContent {
    var shareable: PaeoniaShareable? {
        guard isReady else { return nil }
        let parts = parts
        let title = String(localized: .exquisiteCorpseRevealNumber(number))
        return PaeoniaShareable(title: title) {
            let shared = parts.compactMap { part in
                part.drawing
                    .flatMap {
                        PaeoniaShareRenderer.inkImage(
                            of: $0,
                            canvasSide: GameCanvas.canonicalSide,
                            pixelSide: ExquisiteCorpseShareCard.pixelSide
                        )
                    }
                    .map { ExquisiteCorpseShareCard.Part(ink: $0, credit: part.sharedCredit) }
            }
            guard shared.count == ExquisiteCorpsePartKind.allCases.count else { return nil }
            return PaeoniaShareRenderer.png(
                PaeoniaShareCardFrame(title: title, subtitle: String(localized: .exquisiteCorpseName)) {
                    ExquisiteCorpseShareCard(parts: shared)
                }
            )
        }
    }
}

/// The creature with "Head by Robin" beside each part, so whoever sees the
/// picture knows who drew what. Without both names the figure shows alone.
private struct ExquisiteCorpseShareCard: View {
    struct Part {
        let ink: UIImage
        let credit: String?
    }

    let parts: [Part]

    /// A part is narrower than the card, so the figure fits on a phone screen
    /// when it is sent on.
    static let side: CGFloat = 200
    static let pixelSide: CGFloat = side * 3
    private static let hairline: CGFloat = 2

    var body: some View {
        let credits = parts.compactMap(\.credit)
        if credits.count == parts.count {
            HStack(spacing: PaeoniaSpacing.space12) {
                figure
                VStack(spacing: 0) {
                    ForEach(parts.indices, id: \.self) { index in
                        Text(verbatim: credits[index])
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                            .frame(maxWidth: .infinity, minHeight: Self.side, maxHeight: Self.side, alignment: .leading)
                    }
                }
            }
        } else {
            figure
        }
    }

    private var figure: some View {
        VStack(spacing: 0) {
            ForEach(parts.indices, id: \.self) { index in
                Image(uiImage: parts[index].ink)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.side, height: Self.side)
                    .accessibilityHidden(true)
            }
        }
        .background(.paeoniaBackgroundPrimary)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                ForEach(Array(1..<max(parts.count, 2)), id: \.self) { index in
                    Rectangle()
                        .fill(.paeoniaTextTertiary.opacity(0.3))
                        .frame(height: Self.hairline)
                        .offset(y: Self.side * CGFloat(index) - Self.hairline / 2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .strokeBorder(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeEmphasis)
        }
    }
}
