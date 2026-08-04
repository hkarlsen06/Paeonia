import SwiftUI

/// Shared scaffold for a screen opened from the Me tab menu: it scrolls, keeps the
/// app background, and uses the compact title so the row the user tapped stays
/// recognisable at the top.
struct SettingsDetailScreen<Content: View>: View {
    private let title: LocalizedStringResource
    private let content: Content

    init(
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
                content
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
