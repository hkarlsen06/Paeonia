import SwiftUI

/// The info button after the distance on Home's map. It opens who made the map, which
/// OpenStreetMap's and OpenMapTiles' licences ask Paeonia to show.
struct HomeMapCreditsButton: View {
    @State private var isOpen = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Image(systemName: "info.circle")
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .padding(.leading, PaeoniaSpacing.space4)
                .frame(
                    minWidth: PaeoniaSpacing.compactButtonHeight,
                    minHeight: PaeoniaSpacing.compactButtonHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.homeMapCreditsLabel))
        .accessibilityIdentifier("home.map.credits")
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            credits
                .presentationCompactAdaptation(.popover)
        }
    }

    private var credits: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                link(.homeMapCreditsOpenStreetMap, "https://www.openstreetmap.org/copyright")
                link(.homeMapCreditsOpenFreeMap, "https://openfreemap.org")
                link(.homeMapCreditsOpenMapTiles, "https://openmaptiles.org")
            }
            .padding(.horizontal, PaeoniaSpacing.space16)
            .padding(.vertical, PaeoniaSpacing.space8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: PaeoniaSpacing.focusedContentWidth, idealHeight: contentHeight > 0 ? contentHeight : nil)
    }

    @ViewBuilder
    private func link(_ title: LocalizedStringResource, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
