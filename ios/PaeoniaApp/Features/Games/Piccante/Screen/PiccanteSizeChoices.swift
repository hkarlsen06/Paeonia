import SwiftUI

struct PiccanteSizeChoices: View {
    let choose: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
        layout {
            ForEach([3, 4, 5], id: \.self) { size in
                Button {
                    choose(size)
                } label: {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        miniature(size)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                        Text(verbatim: "\(size) × \(size)")
                            .font(PaeoniaTypography.bodyEmphasis)
                    }
                    .padding(.vertical, PaeoniaSpacing.space16)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                    .paeoniaCardSurface(
                        in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16), fill: Color.paeoniaSurfaceSecondary)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityLabel(Text(.piccanteBoxSize(size, size)))
                .accessibilityIdentifier("piccante.size.\(size)")
            }
        }
    }

    private func miniature(_ size: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: size), spacing: 3) {
            ForEach(0..<(size * size), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.paeoniaInkGold)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
