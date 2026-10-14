import SwiftUI

/// One of the three opening lines Paeonia offers. The line shows in the serif
/// italic it will have on the page.
struct StoryChainOpeningRow: View {
    let text: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StoryChainChoiceRowFrame(isSelected: isSelected) {
                Text(verbatim: text)
                    .font(StoryChainPageStyle.bodyFont.italic())
                    .lineSpacing(StoryChainPageStyle.lineSpacing)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// "Start with your own line", for a story without an opening.
struct StoryChainOwnLineRow: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StoryChainChoiceRowFrame(isSelected: isSelected, trailingSymbol: "square.and.pencil") {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(.storyChainChooseOwn)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Text(.storyChainChooseOwnSubtitle)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("storyChain.opening.own")
    }
}

/// The card around a choice: a check when selected, an optional symbol when not.
private struct StoryChainChoiceRowFrame<Content: View>: View {
    let isSelected: Bool
    var trailingSymbol: String?
    @ViewBuilder var content: Content

    private let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            content
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
                    .transition(.scale.combined(with: .opacity))
            } else if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
            }
        }
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? .paeoniaAccentPrimary : .clear,
                lineWidth: PaeoniaRadius.strokeEmphasis
            )
        }
        .contentShape(shape)
    }
}
