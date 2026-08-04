import SwiftUI

/// A group of settings menu rows: an optional heading above one card whose rows are
/// separated by hairline dividers.
///
/// The Me tab is a menu, so a card here frames a repeated row list rather than
/// decorating ordinary screen content. Place the controls themselves on the screen
/// each row opens.
struct SettingsMenuSection<Content: View>: View {
    private let title: LocalizedStringResource?
    private let content: Content

    init(
        title: LocalizedStringResource? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            if let title {
                Text(title)
                    .font(PaeoniaTypography.sectionTitle)
                    .foregroundStyle(.paeoniaTextSecondary)
            }

            PaeoniaCard(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

/// The hairline between two rows inside a `SettingsMenuSection`.
struct SettingsMenuDivider: View {
    var body: some View {
        Divider()
            .overlay(.paeoniaSurfacePressed)
    }
}
